# frozen_string_literal: true

require 'sinatra'
require 'yaml'

require_relative 'services/dmptool/dmptool_service'
require_relative 'services/dmphub/data_management_plan_service'
require_relative 'services/nsf/awards_scanner_service'

configure do
  p Dir.pwd
  set config: YAML.safe_load(File.open("#{Dir.pwd}/config.yml"))
end

get '/' do
  erb :index
end

# rubocop:disable Metrics/BlockLength
post '/scan' do
  plan_ids = params[:plan_ids].split(',') || []
  plan_ids = plan_ids.map(&:strip)

  dmptool = Dmptool::DmptoolService.new(config: settings.config['dmptool'], plan_ids: plan_ids)
  # dmphub = Dmphub::DataManagementPlanService.new(config: settings.config['dmphub'])
  nsf = Nsf::AwardsScannerService.new(config: settings.config['nsf'])
  # scanned = []

  stream do |out|
    if plan_ids.any?
      out << 'Gathering DMPs from the DMPTool ... please wait<br>'

      dmps = dmptool.retrieve_plans

      if dmps.any?
        dmps.each do |dmp|
          # doi = dmphub.publish_data_management_plan(hash: dmp)
          # next if doi.nil?

          # p dmp.inspect

          # out << "&nbsp;&nbsp;Registered DMP - (DMPTool: #{dmp.fetch('dmp_id', {})['identifier']}, DMPHub: #{doi})<br>"
          id = dmp.fetch('dmp_id', {})['identifier']
          out << "&nbsp;&nbsp;&nbsp;&nbsp;Scanning Awards API for #{id} -- `#{dmp['title']}`<br>"
          authors = dmp.fetch('contributor', [])
                       .map { |c| "#{c['name']} from #{c.fetch('affiliation', {})['name']}" }
                       .join(', ')
          out << "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;with author(s): #{authors}<br>"

          begin
            award = nsf.find_award_by_title(plan: dmp) || {}
            # scanned << doi

            out << '&nbsp;&nbsp;&nbsp;&nbsp;No matches found :(<br>' if award.empty?
            if award.any?

p "AWARD FOUND for #{id} !!!!!!!!!!!!!!!!!!!!!!!"
p award.inspect

              out << "&nbsp;&nbsp;&nbsp;&nbsp;<strong>Found award</strong>: <a target=\"_blank\" href=\"#{award[:award_id]}\">#{award[:award_id]}</a><br>"
              out << "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<strong>Title</strong>: #{award[:title]}<br>"
              award[:principal_investigators].each do |pi|
                out << "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<strong>Investigator</strong>: #{pi[:name]} from #{pi[:organization]}<br>"
              end

              out << '<br>&nbsp;&nbsp;&nbsp;&nbsp;Sending award information back to the DMP Registry<br>'
              awarded = dmphub.register_award(dmp: dmp, award: award)
              # rubocop:disable Metrics/BlockNesting
              out << '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Sucess' if awarded
              out << '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Something went wrong' unless awarded
              # rubocop:enable Metrics/BlockNesting
            end
            out << '<hr>'
          rescue StandardError => e
            out << "&nbsp;&nbsp;&nbsp;&nbsp;<strong>ERROR</strong>: #{e.message}"
            out << '<hr>'
            next
          end
        end
      else
        out << 'Unable to retrieve the plans from the DMPTool.'
      end
    else
      out << 'You must specify at least one plan id!'
    end
    # Always write out the processed file even if code is interrupted!
    # file = File.open("#{Dir.pwd}/processed.yml", 'w')
    # file.write((processed + scanned).flatten.uniq)
    # file.close
  end
  # rubocop:enable Metrics/BlockLength
end
