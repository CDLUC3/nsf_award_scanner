require 'httparty'

module Dmphub
  class DataManagementPlanService

    DEFAULT_HEADERS = headers = {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      'Accept': 'application/json'
    }.freeze

    NSF_DOI = 'https://dx.doi.org/10.13039/100000001'.freeze

    def initialize(config:)
      @client_uid = "#{config['client_uid']}"
      @client_secret = "#{config['client_secret']}"
      @agent = "#{config['user_agent']}"

      @base_path = "#{config['base_path']}"
      @auth_path = "#{@base_path}#{config['token_path']}"
      @index_path = "#{@base_path}#{config['index_path']}"
      @update_path = "#{@base_path}#{config['update_path']}"
      @errors = []

      retrieve_auth_token
    end

    def data_management_plans
      retrieve_auth_token if @token.nil?
      p @errors.join(', ') if @errors.any?
      return [] if @token.nil?

      resp = HTTParty.get(@index_path, headers: authenticated_headers)
      payload = JSON.parse(resp.body)

      @errors << "#{payload['error']} - #{payload['error_description']}" unless resp.code == 200
      @errors << payload.fetch('errors', [])
      p @errors.flatten.join(', ') if @errors.any?
      return [] unless resp.code == 200 || payload.fetch('content', nil).present?

      payload['content'].fetch('dmps', [])
    end

    def register_award(dmp:, award:)
      return false if dmp.nil? or award.nil?

      retrieve_auth_token if @token.nil?
      p @errors.join(', ') if @errors.any?
      return false if @token.nil?

      target = dmp['uri']
      body = award_to_rda_common_standard(dmp: dmp, award: award)

p body.inspect

      return false if body.nil?

      resp = HTTParty.put(target, body: body.to_json, headers: authenticated_headers)
      payload = JSON.parse(resp.body)

p resp.body
p resp.code

      @errors << "#{payload['error'] - payload['error_description']}" unless resp.code == 200
      @errors << payload.fetch('errors', [])
      p @errors.flatten.join(', ') if @errors.any?

      resp.code == 200
    end

    private

    def award_to_rda_common_standard(dmp:, award:)
      return nil if dmp['uri'].nil?

      doi = dmp['uri'].gsub('http://localhost:3003/api/v1/data_management_plans/', '')

      staff = award[:principal_investigators].select { |p| !p[:name].nil? }.map do |pi|
        {
          "name": pi[:name],
          "contributor_type": 'investigator',
          "organizations": [{
            "name": pi[:organization]
          }]
        }
      end

      {
        "dmp": {
          "dm_staff": staff,
          "project": {
            "funding": [{
              "funder_id": NSF_DOI,
              "grant_id": award[:award_id],
              "funding_status": "granted"
            }]
          }
        }
      }
    end

    def retrieve_auth_token
      payload = {
        grant_type: 'client_credentials',
        client_id: @client_uid,
        client_secret: @client_secret
      }
      resp = HTTParty.post(@auth_path, body: payload, headers: DEFAULT_HEADERS)
      response = JSON.parse(resp.body)
      @token = response if resp.code == 200
      @errors << "#{payload['error']} - #{payload['error_description']}" unless resp.code == 200
    rescue StandardError => se
      @errors << se.message
      return nil
    end

    def authenticated_headers
      agent = "#{@agent} (#{@client_uid})"
      DEFAULT_HEADERS.merge({
        'User-Agent': agent,
        'Authorization': "#{@token['token_type']} #{@token['access_token']}",
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      })
    end

  end
end
