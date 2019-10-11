require_relative '../../services/dmphub/data_management_plan_service'
require_relative '../../services/nsf/awards_scanner_service'

config = YAML.load(File.open("#{Dir.pwd}/config.yml"))

text = File.read("#{Dir.pwd}/processed.yml")
text.gsub!(/\r\n?/, '\n')
processed = text.each_line.map { |line| line }
recorder = File.open("#{Dir.pwd}/processed.yml", 'a')

dmphub = Dmphub::DataManagementPlanService.new(config: config['dmphub'])
nsf = Nsf::AwardsScannerService.new(config: config['nsf'])

plans = dmphub.data_management_plans
p 'No DOIs found' if plans.empty?

counter = 0

plans.each do |plan|
  doi = plan['uri'].gsub('http://localhost:3003/api/v1/data_management_plans/', '')

#break if counter > 10
#next unless ['10.80030/5zhm-9t89'].include?(doi)

  next if processed.include?("#{doi}\n")

  counter += 1
  p "#{counter + 1}) Scanning Awards API for DMP: `#{plan['title']}` (#{doi})"
  p "  with author(s): #{plan['authors'].gsub('|', ' from ')}"

  #begin
    award = nsf.find_award_by_title(agency: 'NSF', plan: plan) || {}
    recorder.puts doi
    p '    no matches found' if award.empty?
    if award.any?
      p "     Found award: #{award[:award_id]}"
      p "       Title: #{award[:title]}"
      award[:principal_investigators].each do |pi|
        p "       Investigator: #{pi[:name]} from #{pi[:organization]}"
      end

      p "    Sending award information back to the DMPHub"
      if dmphub.register_award(dmp: plan, award: award)
        p "       Sucess"
      else
        p "       Something went wrong"
      end
    end
    p "-------------------------------------"

  #rescue StandardError => se
  #  p "     ERROR: #{se.class.name} - #{se.message}"
  #  p "-------------------------------------"
  #  next
  #end
end

recorder.close
