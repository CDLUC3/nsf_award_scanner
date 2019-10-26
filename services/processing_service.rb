# frozen_string_literal: true

require_relative './dmphub/data_management_plan_service'
require_relative './nsf/awards_scanner_service'

class ProcessingService

  NSF = 'http://dx.doi.org/10.13039/100000001'
  NASA = 'http://dx.doi.org/10.13039/100000104'

  def initialize
    @config = YAML.load(File.open("#{Dir.pwd}/config.yml"))
    open_processed
    @dmphub = Dmphub::DataManagementPlanService.new(config: @config['dmphub'])
    @nsf = Nsf::AwardsScannerService.new(config: @config['nsf'])
  end

  def process
    open_processed
    @recorder = File.open("#{Dir.pwd}/processed.yml", 'a')

    next_page(url: "#{@config['dmphub']['base_path']}#{@config['dmphub']['index_path']}")

    p "DONE #{Time.now.utc.to_s}"
    @recorder.close
  end

  private

  def open_processed
    text = File.read("#{Dir.pwd}/processed.yml").gsub(/\r\n?/, '\n')
    @processed = text.each_line.map { |line| line }
  end

  # Recursively process the results returned by DMPRegistry
  def next_page(url:)
    p "Scanning DMP Registry @ #{url.to_s} - #{Time.now.utc.to_s}"
    resp = @dmphub.data_management_plans(url: url)
    return nil if resp.fetch(:items, []).empty?

    p "Unable to retrieve funding information from DMPRegistry!" if resp[:errors].any?
    p resp[:errors]  if resp[:errors].any?

    resp[:items].each do |item|
      next if item['funding'].nil? || item['funding']['dmpDOI'].nil?

      award = scan_for_awards(item: item)
      next if award.nil?

      # Register the award with the DMP Registry
      @dmphub.register_award(funding: item.fetch('funding', {}), award: award)
      # record that we have processed this one
      @recorder.puts item['funding']['update_url']
    end

    next_page(url: resp[:next]) unless resp[:next].nil?
  end

  # Scan the NSF Awards API
  def scan_for_awards(item:)
    update_url = item['funding'].fetch('update_url', '')
    funder = item['funding'].fetch('funderId', '')
    return nil if update_url.nil? || funder.nil?

    # Make sure we're working with a funder that the NSF Awards API supports
    case funder
    when NSF
      agency = 'NSF'
    when NASA
      agency = 'NASA'
    end
    return nil if agency.nil?

    # Search the NSF Awards API
    p "Scanning NSF Awards API for: `#{item['funding']['projectTitle']}`"
    p "  with author(s): #{item['funding']['authors'].map { |a| a.gsub('|', ' from ') }.join(', ')}"
    @nsf.find_award_by_title(agency: agency, funding: item.fetch('funding', {}))
  end

end
