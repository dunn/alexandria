# frozen_string_literal: true

require "metadata_ci"

module Parse::CSV
  # Match headers like "lc_subject_type"
  TYPE_HEADER_PATTERN = /\A.*_type\Z/

  # Given a 'type' field from the CSV, determine which object model pertains
  # @param [String] csv_type_field
  # @return [String] the name of the model class
  def self.determine_model(csv_type_field)
    csv_type_field.titleize.gsub(/\s+/, "")
  end

  # The CSV metadata may contain multiple fields with the same header,
  # e.g. multiple :files columns.  Ruby's builtin {CSV} library
  # doesn't handle this very well, so we count them out manually.
  #
  # @param [Symbol] header
  # @param [CSV::Row] row
  # @return [Array]
  def self.values_for(header, row)
    index = row.index(header.to_sym)
    return [] if index.nil?

    Array.new(row.length - index) do |i|
      row.field(header.to_sym, i + index)
    end.compact
  end

  # Maps a row of CSV metadata to the CSV headers
  #
  # @param [CSV::Row] row
  # @return [Hash]
  def self.csv_attributes(row)
    Fields::CSV.all.map do |header|
      key = if header.respond_to? :keys
              header.keys.first
            else
              header
            end

      values = if header.is_a?(Array) && header["subfields"].present?
                 header["subfields"].map do |sub|
                   Fields::CSV.subfield_strings(sub).map do |s|
                     values_for(s, row)
                   end
                 end
               else
                 values_for(key, row)
               end.flatten

      next {} if values.blank?
      next Fields::Transformer.default.call(key, values) if header.is_a? String

      if header[key]["typed"]
        Fields::Transformer.typed(key, values)
      elsif header[key]["transformer"]
        Fields::Transformer.send(header[key]["transformer"], key, values)
      elsif header[key]["subfields"].present?
        Fields::Transformer.subfields(key, values)
      else
        Fields::Transformer.default.call(key, values)
      end
    end.reduce(&:merge)
  end

  # Given an accession_number, get the id of the associated object
  # @param [Array|String] accession_number
  # @return [String] the id of the associated object or nil if nothing found
  def self.get_id_for_accession_number(accession_number)
    a = if accession_number.instance_of? Array
          accession_number.first
        else
          accession_number
        end
    o = ActiveFedora::Base.where(accession_number_ssim: a).first
    return o.id if o
    nil
  end

  # Transform coordinates as provided in CSV spreadsheet into dcmi-box
  # formatting
  #
  # Output should look like 'northlimit=43.039; eastlimit=-69.856;
  # southlimit=42.943; westlimit=-71.032; units=degrees;
  # projection=EPSG:4326'
  #
  # TODO: The transform_coordinates_to_dcmi_box method should invoke a
  # DCMIBox.new method DCMI behaviors should be encapsulated there and
  # it should have a .to_s method
  #
  # @param [Hash] attrs A hash of attributes that will become a fedora object
  # @return [Hash]
  def self.transform_coordinates_to_dcmi_box(attrs)
    return attrs unless attrs[:north_bound_latitude] ||
                        attrs[:east_bound_longitude] ||
                        attrs[:south_bound_latitude] ||
                        attrs[:west_bound_longitude]

    if attrs[:north_bound_latitude]
      north = "northlimit=#{attrs.delete(:north_bound_latitude).first}; "
    end

    if attrs[:east_bound_longitude]
      east = "eastlimit=#{attrs.delete(:east_bound_longitude).first}; "
    end

    if attrs[:south_bound_latitude]
      south = "southlimit=#{attrs.delete(:south_bound_latitude).first}; "
    end

    if attrs[:west_bound_longitude]
      west = "westlimit=#{attrs.delete(:west_bound_longitude).first}; "
    end

    attrs[:coverage] = "#{north}#{east}#{south}#{west}units=degrees; "\
                       "projection=EPSG:4326"
    attrs
  end

  # Process the structural metadata, e.g., parent_id, index_map_id
  #
  # @param [Hash] attrs A hash of attributes that will become a fedora object
  # @param [Hash]
  def self.handle_structural_metadata(attrs)
    a = attrs.delete(:parent_accession_number)
    if a
      parent_id = get_id_for_accession_number(a)
      attrs[:parent_id] = parent_id if parent_id
    end

    # This is an attribute of MapSets, which are generally created
    # before the IndexMap specified in the metadata.  If we use
    # {get_id_for_accession_number}, we'll be setting this attribute
    # to nil since the IndexMap doesn't exist in Fedora yet.  So
    # instead just use the accession number itself.
    im = attrs.delete(:index_map_accession_number)
    attrs[:index_map_id] = im if im.present?

    attrs
  end

  # Sometimes spaces or punctuation make their way into CSV field names.
  # When they do, clean it up.
  #
  # @param [Hash] attrs A hash of attributes that will become a fedora object
  # @return [Hash] the same hash, but with spaces stripped off all the
  #     field names
  def self.strip_extra_spaces(attrs)
    new_h = {}
    attrs.each_pair do |k, v|
      new_k = k.to_s.strip.to_sym
      new_h[new_k] = v
    end
    new_h
  end

  # Given a shorthand string for an access policy,
  # assign the right AccessPolicy object.
  #
  # @param [Hash] attrs A hash of attributes that will become a fedora object
  # @return [Hash]
  def self.assign_access_policy(attrs)
    raise "No access policy defined" unless attrs[:access_policy]
    case attrs.delete(:access_policy)
    when "public"
      attrs[:admin_policy_id] = AdminPolicy::PUBLIC_POLICY_ID
    when "ucsb"
      attrs[:admin_policy_id] = AdminPolicy::UCSB_POLICY_ID
    when "discovery"
      attrs[:admin_policy_id] = AdminPolicy::DISCOVERY_POLICY_ID
    when "public_campus"
      attrs[:admin_policy_id] = AdminPolicy::PUBLIC_CAMPUS_POLICY_ID
    when "restricted"
      attrs[:admin_policy_id] = AdminPolicy::RESTRICTED_POLICY_ID
    when "ucsb_campus"
      attrs[:admin_policy_id] = AdminPolicy::UCSB_CAMPUS_POLICY_ID
    else
      raise "Invalid access policy: #{access_policy}"
    end
    attrs
  end
end
