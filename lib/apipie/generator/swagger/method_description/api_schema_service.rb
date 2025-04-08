class Apipie::Generator::Swagger::MethodDescription::ApiSchemaService
  # @param [Apipie::Generator::Swagger::MethodDescription::Decorator] method_description
  def initialize(method_description, language: nil)
    @method_description = method_description
    @language = language
  end

  # @return [Hash]
  def call
    @method_description.apis.each_with_object({}) do |api, paths|
      api = Apipie::Generator::Swagger::MethodDescription::ApiDecorator.new(api)
      path = Apipie::Generator::Swagger::PathDecorator.new(api.path)
      op_id = Apipie::Generator::Swagger::OperationId.from(api).to_s

      if Apipie.configuration.generator.swagger.generate_x_computed_id_field?
        Apipie::Generator::Swagger::ComputedInterfaceId.instance.add!(op_id)
      end

      parameters = Apipie::Generator::Swagger::MethodDescription::ParametersService
        .new(@method_description, path: path, http_method: api.normalized_http_method)
        .call

      paths[path.swagger_path(@method_description)] ||= {}
      paths[path.swagger_path(@method_description)][api.normalized_http_method] = {
        tags: tags,
        consumes: consumes,
        produces: ["application/json"], # Evira: Forces application/json content type for all documentation
        operationId: op_id,
        summary: api.summary(method_description: @method_description, language: @language),
        parameters: parameters,
        responses: responses(api),
        description: Apipie.app.translate(@method_description.full_description, @language),
        "x-codeSamples": build_code_samples(api), # Evira:
      }.compact
    end
  end

  private

  # Evira: Automatically generates cURL examples from endpoint headers and body params
  def build_code_samples(api)
    return [] unless %w[get post put patch delete].include?(api.http_method.downcase)

    host = Apipie.configuration.swagger_host.present? ? "https://#{Apipie.configuration.swagger_host}" : "http://localhost:3000"
    http_method = api.http_method.upcase

    # Separate query and body params
    query_params = []
    body_params = {}

    @method_description.params.values.each do |param|
      next if param.response_only

      name = param.name.to_s
      example = param.options[:example] || "#{name}_example"

      if param.options[:in] == "query" || http_method == "GET"
        query_params << "#{name}=#{CGI.escape(example.to_s)}"
      else
        body_params[name] = example
      end
    end

    # Construct full URL with query string if needed
    query_string = query_params.any? ? "?#{query_params.join("&")}" : ""
    url = "#{host}#{api.path}#{query_string}"

    # Headers
    headers = []
    if @method_description.headers.present?
      @method_description.headers.each do |header|
        headers << "-H \"#{header[:name]}: #{header[:options][:default] || "<value>"}\""
      end
    else
      headers << "-H \"Content-Type: application/json\"" if http_method != "GET"
    end

    # Data (only for non-GET)
    body_part = ""
    if http_method != "GET" && body_params.any?
      body_part = "-d '#{JSON.pretty_generate(body_params)}'"
    end

    # Combine
    curl_parts = [
      "curl -X #{http_method} \"#{url}\"",
      *headers,
      body_part,
    ].reject(&:empty?).join(" \\\n  ")

    [
      {
        lang: "cURL",
        label: "cURL",
        source: curl_parts,
      },
    ]
  end

  def summary(api)
    translated_description = Apipie.app.translate(api.short_description, @language)

    return translated_description if translated_description.present?

    Apipie::Generator::Swagger::Warning.for_code(
      Apipie::Generator::Swagger::Warning::MISSING_METHOD_SUMMARY_CODE,
      @method_description.ruby_name
    ).warn_through_writer
  end

  def tags
    tags = if Apipie.configuration.generator.swagger.skip_default_tags?
        []
      else
        [@method_description.resource._id]
      end
    tags + warning_tags + @method_description.tag_list.tags
  end

  def warning_tags
    if Apipie.configuration.generator.swagger.include_warning_tags? &&
       Apipie::Generator::Swagger::WarningWriter.instance.issued_warnings?
      ["warnings issued"]
    else
      []
    end
  end

  def consumes
    if params_in_body?
      ["application/json"]
    else
      ["application/x-www-form-urlencoded", "multipart/form-data"]
    end
  end

  def params_in_body?
    Apipie.configuration.generator.swagger.content_type_input == :json
  end

  # @param [Apipie::Generator::Swagger::MethodDescription::ApiDecorator] api
  def responses(api)
    Apipie::Generator::Swagger::MethodDescription::ResponseService
      .new(
        @method_description,
        language: @language,
        http_method: api.normalized_http_method,
      )
      .call
  end
end
