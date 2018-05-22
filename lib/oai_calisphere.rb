# frozen_string_literal: true

class OAICalisphere < OAI::Provider::Metadata::Format
  def initialize
    @prefix = "oai_dc"
    @schema = "https://digitalcollections.library.ucsc.edu/oai_dpla/oai_dpla.xsd"
    @namespace = "http://www.openarchives.org/OAI/2.0/oai_dc/"
    @element_namespace = "dc"
  end

  PREFIXES = {
    dc: {
      contributor: "all_contributors_label_sim",
      coverage:    "location_label_tesim",
      creator:     "creator_label_tesim",
      date:        "date_si",
      description: %w[description_tesim note_label_tesim citation],
      format:      "form_of_work_label_tesim",
      identifier:  "uri_ssm",
      language:    "language_label_ssm",
      publisher:   "publisher_tesim",
      relation:    "collection_label_ssim",
      rights:      "license_tesim",
      subject:     "lc_subject_label_tesim",
      title:       "title_tesim",
    },
    edm: {
      isShownAt: lambda do |record|
        (record["image_url_ssm"] || []).map do |path|
          "https://#{Rails.application.config.host_name}#{path}"
        end
      end,
    },
  }.freeze

  def header_specification
    {
      "xmlns:dc" => "http://purl.org/dc/elements/1.1/",
      "xmlns:edm" => "http://www.europeana.eu/schemas/edm/",
      "xmlns:oai_dc" => "http://www.openarchives.org/OAI/2.0/oai_dc/",
      "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
      "xsi:schemaLocation" => %(
        https://digitalcollections.library.ucsc.edu/oai_dpla/
        https://digitalcollections.library.ucsc.edu/oai_dpla/oai_dpla.xsd
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
