# frozen_string_literal: true

require 'httparty'

module Dmptool
  # This service uses the NSF Award Search Web API (ASWA). For more information
  # refer to: https://www.nsf.gov/developer/
  class DmptoolService
    def initialize(config:, plan_ids: [])
      @base_url = config['base_url']
      @show_path = "#{@base_url}#{config['show_path']}"
      @auth_path = "#{@base_url}#{config['auth_path']}"
      @plan_ids = plan_ids
      @user_agent = config['user_agent']
      @client_id = config['client_id']
      @client_secret = config['client_secret']
      @errors = []
      authenticate
    end

    # rubocop:disable Metrics/MethodLength
    def retrieve_plans
      return [] if @plan_ids.nil? || @plan_ids.empty?

      authenticate if @token.nil?
      ret = []
      @plan_ids.each do |plan_id|
        opts = {
          headers: authenticated_headers,
          follow_redirects: true
        }
        resp = HTTParty.get(format(@show_path, id: plan_id), opts)
        json = JSON.parse(resp.body)
        ret << json.fetch('items', []).first&.fetch('dmp', {}) if resp.code == 200
      end
      ret
    end
    # rubocop:enable Metrics/MethodLength

    private

    def headers
      {
        'User-Agent': "#{@user_agent} (#{@client_id})",
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'Accept': 'application/json'
      }
    end

    def authenticated_headers
      headers.merge(
        {
          'Authorization': "#{@token['token_type']} #{@token['access_token']}",
          'Content-Type': 'application/json'
        }
      )
    end

    # rubocop:disable Metrics/MethodLength
    def authenticate
      payload = {
        grant_type: 'client_credentials',
        client_id: @client_id,
        client_secret: @client_secret
      }
      resp = HTTParty.post(@auth_path, body: payload.to_json, headers: headers)
      response = JSON.parse(resp.body)
      @token = response if resp.code == 200
      p "#{payload['error']} - #{payload['error_description']}" unless resp.code == 200
    rescue StandardError => e
      p e.message
      @errors << e.message
      nil
    end
    # rubocop:enable Metrics/MethodLength
  end
end
