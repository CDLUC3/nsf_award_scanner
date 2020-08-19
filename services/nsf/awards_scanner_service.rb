# frozen_string_literal: true

require 'amatch'
require 'httparty'
require 'stopwords'

module Nsf
  # This service uses the NSF Award Search Web API (ASWA). For more information
  # refer to: https://www.nsf.gov/developer/
  # rubocop:disable Metrics/ClassLength
  class AwardsScannerService
    SHOW_AWARD_URL = 'https://www.nsf.gov/awardsearch/showAward?AWD_ID='

    include Amatch

    def initialize(config:)
      @agent = 'California Digital Library (CDL) - contact: brian.riley@ucop.edu'
      @base_path = config['base_path'].to_s
      # rubocop:disable Style/FormatStringToken
      @awards_path = "#{@base_path}#{config['awards_path']}?keyword=%{words}"
      # rubocop:enable Style/FormatStringToken
      @errors = []
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def find_award_by_title(_agency:, funding:)
      return {} if funding.nil? || funding.fetch('projectTitle', nil).nil?

      url = format(@awards_path.to_s, words: cleanse_title(title: funding['projectTitle']))
      url = CGI.encode(url.gsub(/\s/, '+'))
      fields = %w[id title piName piEmail abstractText projectOutComesReport poName poEmail
                  dunsNumber startDate expDate awardeeName fundProgramName pdPIName perfLocation
                  primaryProgram transType awardee publicationResearch publicationConference
                  fundAgencyCode awardAgencyCode].join(',')
      url += "&printFields=#{fields}"

      resp = HTTParty.get(url, headers: headers)
      p "Received a #{resp.code} from the NSF Awards API for: #{url}" unless resp.code == 200
      p resp.body unless resp.code == 200
      return {} unless resp.code == 200

      payload = JSON.parse(resp.body)
      scores = []
      payload.fetch('response', {}).fetch('award', []).each do |award|
        next if award.fetch('title', nil).nil? || award.fetch('pdPIName', nil).nil?

        score = process_response(
          funding: funding,
          title: award.fetch('title', nil),
          investigator: award.fetch('pdPIName', nil),
          org: award.fetch('awardeeName', nil)
        )

        # If the score is above 0.6 but below 0.9 record it so we can evaluate
        record_findings(funding: funding, json: payload, score: score) if score >= 0.5 && score <= 0.64

        scores << { score: score, hash: award } if score >= 0.64
      end
      filter_scores(scores: scores)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def parse_author(author:)
      return nil if author.nil?

      parts = author.split('|')
      { author: parts.first, organization: parts.last }
    end

    private

    def headers
      {
        'User-Agent': 'California Digital Library (CDL) - contact: brian.riley@ucop.edu',
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'Accept': 'application/json'
      }
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def filter_scores(scores:)
      return nil unless scores.any?

      top_score = scores.min { |a, b| b.fetch(:score, 0.0) <=> a.fetch(:score, 0.0) }
      top_score_title = top_score.fetch(:hash, {}).fetch('title', '')

      pis = scores.select { |s| s.fetch(:hash, {}).fetch('title', '') == top_score_title }
                  .collect do |s|
                    {
                      name: s.fetch(:hash, {}).fetch('pdPIName', ''),
                      email: s.fetch(:hash, {}).fetch('piEmail', ''),
                      organization: s.fetch(:hash, {}).fetch('awardeeName', '')
                    }
                  end
      {
        title: top_score_title,
        description: top_score.fetch(:hash, {}).fetch('abstractText', nil),
        project_start: top_score.fetch(:hash, {}).fetch('startDate', nil),
        project_end: top_score.fetch(:hash, {}).fetch('expDate', nil),
        principal_investigators: pis,
        program_officer: {
          name: top_score.fetch(:hash, {}).fetch('poName', nil),
          email: top_score.fetch(:hash, {}).fetch('poEmail', nil),
          organization: top_score.fetch(:hash, {}).fetch('awardAgencyCode', '4900')
        },
        award_id: "#{SHOW_AWARD_URL}#{top_score.fetch(:hash, {}).fetch('id', '')}",
        identifiers: {
          fund_program: top_score.fetch(:hash, {}).fetch('fundProgramName', nil),
          primary_program: top_score.fetch(:hash, {}).fetch('primaryProgram', nil)
        }
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def record_findings(funding:, json:, score:)
      file = File.open("#{Dir.pwd}/findings.log", 'a')
      file.puts '==================================================='
      file.puts '==================================================='
      file.puts 'DMP JSON RECEIVED FROM DMPRegistry:'
      file.puts funding.to_json
      file.puts '---------------------------------------------------'
      file.puts 'NSF AWARD API RESULTS:'
      file.puts json.to_json
      file.puts '---------------------------------------------------'
      file.puts score.to_json
      file.close
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
    def process_response(funding:, title:, investigator:, org:)
      title_score = proximity_check(
        text_a: cleanse_title(title: funding.fetch('projectTitle', nil)),
        text_b: cleanse_title(title: title)
      )
      return title_score if funding.fetch('authors', nil).nil?

      persons = funding.fetch('authors', [])
      return 0.0 if funding.nil? || title.nil?

      auth_hash = persons.map do |a|
        a.split('|')
        {
          author: a[0],
          organization: a[1]
        }
      end
      auths = auth_hash.collect { |a| a[:author] }
      orgs = auth_hash.collect { |o| o[:organization] }

      title_score = title_scoring(
        title_a: cleanse_title(title: funding.fetch('projectTitle', nil)),
        title_b: cleanse_title(title: title)
      )
      return title_score if (orgs.empty? && auths.empty?) || title_score < 0.7

      pi_org_score = org_scoring(orgs: orgs, pi_org: org)
      pi_score = author_scoring(authors: auths, investigator: investigator)
      title_score + pi_score + pi_org_score
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity

    def title_scoring(title_a:, title_b:)
      return 0.0 if title_a.nil? || title_b.nil?

      proximity_check(
        text_a: cleanse_title(title: title_a),
        text_b: cleanse_title(title: title_b)
      )
    end

    def org_scoring(orgs:, pi_org:)
      return 0.0 if orgs.empty? || pi_org.nil?

      orgs.reduce(0.0) { |sum, org| sum + proximity_check(text_a: org, text_b: pi_org) }
    end

    def author_scoring(authors:, investigator:)
      return 0.0 if authors.empty? || investigator.nil?

      authors.reduce(0.0) { |sum, auth| sum + proximity_check(text_a: auth, text_b: investigator) }
    end

    def cleanse_title(title:)
      # DMPs ofter start with a name of the grant type (e.g. 'EAGER:'') so strip these off
      ret = title.include?(':') ? title.split(':').last : title
      # Remove non alphanumeric, space or dash characters
      ret = ret.gsub!(/[^0-9a-z\s\-]/i, '') if ret.match?(/[^0-9a-z\s\-]/i)
      # If ret is nil for any reason just use the unaltered title
      ret = title if ret.nil?
      # Remove stop words like 'The', 'An', etc.
      ret.split(' ').reject { |w| Stopwords.is?(w) }.join(' ')
    end

    def proximity_check(text_a:, text_b:)
      return nil if text_a.nil? || text_b.nil?

      text_a.to_s.levenshtein_similar(text_b.to_s)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
