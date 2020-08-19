# frozen_string_literal: true

require 'httparty'

module Dmphub
  # Interface to the DMP Registry's API
  # rubocop:disable Metrics/ClassLength
  class DataManagementPlanService
    # Expecting the following format from DMP Regsitry:
    # {
    #   "application"=>"Dmphub",
    #   "status"=>"OK",
    #   "time"=>"2019-10-26 15:33:59 UTC",
    #   "caller"=>"national_science_foundation",
    #   "source"=>"GET http://localhost:3003/api/v0/awards?page=2&per_page=25",
    #   "page"=>2,
    #   "per_page"=>25,
    #   "total_items"=>662,
    #   "prev"=>"http://localhost:3003/api/v0/awards?page=1&per_page=25",
    #   "next"=>"http://localhost:3003/api/v0/awards?page=3&per_page=25",
    #   "items"=>[
    #     {
    #       "funding"=>{
    #         "projectTitle"=>"Research on cool genomic anomolies",
    #         "projectStartOn"=>"2012-03-26 14:28:33 UTC",
    #         "projectEndOn"=>"2014-03-26 14:28:33 UTC",
    #         "authors"=>["John Doe|Montana State University (MSU)"]
    #         "update_url"=>"http://localhost:3003/api/v0/awards/1",
    #         "funderId"=>"http://dx.doi.org/10.13039/100000001",
    #         "funderName"=>"National Science Foundation (NSF)",
    #         "grantId"=>nil,
    #         "fundingStatus"=>"planned"
    #       }
    #     }
    #   ]
    # }
    #
    # The `update_url` is the target we want to send our changes to!
    # The `next` is the url for the next page

    DEFAULT_HEADERS = {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      'Accept': 'application/json'
    }.freeze

    NSF_DOI = 'http://dx.doi.org/10.13039/100000001'

    def initialize(config:)
      @client_uid = config['client_uid'].to_s
      @client_secret = config['client_secret'].to_s
      @agent = config['user_agent'].to_s

      @base_path = config['base_path'].to_s
      @auth_path = "#{@base_path}#{config['token_path']}"
      @errors = []

      retrieve_auth_token
    end

    def data_management_plans(url:)
      retrieve_auth_token if @token.nil?
      return [] if @token.nil?

      resp = HTTParty.get(url, headers: authenticated_headers)
      payload = JSON.parse(resp.body)
      {
        next_page: payload.fetch('next', nil),
        items: payload.fetch('items', []),
        errors: payload.fetch('errors', [])
      }
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def register_award(funding:, award:)
      return false if funding.nil? || award.nil?

      retrieve_auth_token if @token.nil?
      return false if @token.nil?

      target = funding['update_url']
      body = award_to_rda_common_standard(funding: funding, award: award)
      return false if body.nil? || target.nil?

      # TODO: For some reason the hub is returning URLs with port 3000 even when its
      #       running on port 3003, so this is a hack to temporarily address that
      target = target.gsub(':3000', ':3003')

      resp = HTTParty.put(target, body: body.to_json, headers: authenticated_headers)

      return resp.headers['location'] if resp.code == 204

      payload = JSON.parse(resp.body)
      p payload['errors'] unless payload['error'].nil?
      false
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def register_person(funding:, award:); end

    private

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity
    def award_to_rda_common_standard(funding:, award:)
      return nil if funding['dmpDOI'].nil?

      staff = award[:principal_investigators].reject { |p| p[:name].nil? }.map do |pi|
        {
          "name": pi[:name],
          "mbox": pi[:email],
          "contributorType": 'investigator',
          "organizations": [{
            "name": pi[:organization]
          }]
        }
      end

      unless award[:program_officer][:name].nil?
        prog = 'National Aeronautics and Space Administration (NASA)'
        prog = 'National Science Foundation (NSF)' if award[:program_officer][:organization] == '4900'
        staff << {
          "name": award[:program_officer][:name],
          "mbox": award[:program_officer][:email],
          "contributorType": 'program_officer',
          "organizations": [{ "name": prog }]
        }
      end

      ids = []
      is_funded = award[:identifiers][:fund_program].nil?
      is_primary = award[:identifiers][:primary_program].nil?
      ids << { 'category': 'sub_program', value: award[:identifiers][:fund_program] } unless is_funded
      ids << { 'category': 'program', value: award[:identifiers][:primary_program] } unless is_primary

      # We send back the `dmpDOI` so that the DMPRegistry can verify that we are
      # working with the correct DMP
      {
        "dmp": {
          "dmpIds": [{
            'category': 'doi',
            'value': funding['dmpDOI']
          }],
          "dmStaff": staff,
          "project": {
            "startOn": award[:project_start],
            "endOn": award[:project_end],
            "funding": [{
              "funderId": funding['funderId'],
              "grantId": award[:award_id],
              "fundingStatus": 'granted',
              "awardIds": ids
            }]
          }
        }
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity

    # rubocop:disable Metrics/MethodLength
    def retrieve_auth_token
      payload = {
        grant_type: 'client_credentials',
        client_id: @client_uid,
        client_secret: @client_secret
      }
      resp = HTTParty.post(@auth_path, body: payload, headers: DEFAULT_HEADERS)
      response = JSON.parse(resp.body)
      @token = response if resp.code == 200
      p "#{payload['error']} - #{payload['error_description']}" unless resp.code == 200
    rescue StandardError => e
      @errors << e.message
      nil
    end
    # rubocop:enable Metrics/MethodLength

    def authenticated_headers
      agent = "#{@agent} (#{@client_uid})"
      DEFAULT_HEADERS.merge(
        {
          'User-Agent': agent,
          'Authorization': "#{@token['token_type']} #{@token['access_token']}",
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        }
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
