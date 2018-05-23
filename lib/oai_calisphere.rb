# frozen_string_literal: true

class OAICalisphere < OAI::Provider::Metadata::Format
  def initialize
    @prefix = "oai_cdl"
    @schema = "https://alexandria.ucsb.edu/oai_cdl.xsd"
    @namespace = "http://www.openarchives.org/OAI/2.0/"
    @element_namespace = "cdl"
  end

  PREFIXES = {
    dc: {
      contributor: "all_contributors_label_sim",
      creator:     "creator_label_tesim",
      date:        "date_si",
      description: %w[description_tesim note_label_tesim citation],
      format:      "extent_ssm",
      identifier:  "identifier_ssm",
      language:    "language_label_ssm",
      publisher:   "publisher_tesim",
      relation:    "collection_label_ssim",
      rights:      "copyright_status_label_tesim",
      subject:     "lc_subject_label_tesim",
      title:       "title_tesim",
    },
    dcterms: {
      accessRights: "isGovernedBy_ssim",
      alternative: "alternative_tesim",
      isPartOf: "collection_label_ssim",
      rightsHolder: "rights_holder_label_tesim",
      spatial: "location_label_tesim",
      type: "work_type_label_tesim",
    },
    edm: {
      isShownAt: "uri_ssm",
      hasType: "form_of_work_label_tesim",
      object: lambda do |record|
        (record["image_url_ssm"] || []).map do |path|
          "https://#{Rails.application.config.host_name}#{path}"
        end
      end,
      rights: "license_tesim",
    },
  }.freeze

  def header_specification
    {
      "xmlns:dc" => "http://purl.org/dc/elements/1.1/",
      "xmlns:dcterms" => "http://purl.org/dc/terms/",
      "xmlns:edm" => "http://www.europeana.eu/schemas/edm/",
      "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
      "xsi:schemaLocation" => %(
        https://alexandria.ucsb.edu/oai_cdl/
        https://alexandria.ucsb.edu/oai_cdl.xsd
      ).gsub(/\s+/, " "),
    }
  end

  def encode(_model, record)
    xml = Builder::XmlMarkup.new

    xml.tag!("#{prefix}:#{element_namespace}", header_specification) do
      PREFIXES.each do |pref, fields|
        fields.each do |k, v|
          values = if v.class == Proc
                     v.call(record)
                   else
                     value_for(v, record.to_h, {})
                   end

          # byebug if values.present?

          values.each do |value|
            xml.tag! "#{pref}:#{k}", value
          end
        end
      end
    end

    xml.target!
  end

  def value_for(field, record, _map)
    Array(field).map do |f|
      record[f] || []
    end.flatten.compact
  end
end
