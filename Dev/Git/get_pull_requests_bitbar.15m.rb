#!/usr/bin/env ruby
# frozen_string_literal: true

# <bitbar.title>PR Counts for Github and Bitbucket</bitbar.title>
# <bitbar.version>v2.0.0</bitbar.version>
# <bitbar.author>Marco Cabazal</bitbar.author>
# <bitbar.author.github>MarcoCabazal</bitbar.author.github>
# <bitbar.desc>Gets Pull Request Counts for Github and Bitbucket Repos</bitbar.desc>
# <bitbar.image>https://marcocabazal.github.io/images/gpr_snap.png</bitbar.image>
# <bitbar.dependencies>ruby >= 2</bitbar.dependencies>

# contributor
# <bitbar.author>Yogesh Lonkar</bitbar.author>
# <bitbar.author.github>yogeshlonkar</bitbar.author.github>

###### README
# Please secure the app-specific password/personal access token from either Bitbucket or Github.
# These tokens are necessary to raise request limits and for the script to have read access to
# private repositories.
#
# For Bitbucket: From your profile page, click on Bitbucket Settings -> App Passwords
# For Github: Click on your avatar, then go to Settings -> Personal Access Tokens
#
#
# Run frequency of this script is defined by the filename, i.e., for
# the default get_pull_requests_bitbar.1h.rb, frequency is every hour.
#
# You may rename this script with the following options to fine-tune.
# Options: {n}s for seconds
#          {n}m for minutes
#          {n}h for hours
#          {n}d for days
######################################################################################################################
## REQUIRES NERD-FONTS all or just https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/DejaVuSansMono ##
######################################################################################################################
###### EXTRA
# When run from bitbar or if filename contains the word bitbar, output is
# multiline (click menu item to see details), otherwise, it just outputs
# the total PR counts (good for use with BetterTouchTool). To use with BetterTouchTool,
# just create a symlink to this script without the word bitbar and refer to that link instead.

###### BEGIN_CONFIG
REPOS_YAML = File.expand_path "#{__dir__}/configs/repos.yaml"
###### Sample YAML config
# username: "your-github-username-not-your-email-used-if-not-set-per-repo"
# app_password: "personal-access-token-used-if-not-set-per-repo"
# repos:
#   - name: "Bitbar Plugins"
#     service: "github"
#     repo: "matryer/bitbar-plugins"
#
#   - name: "Bitbar Plugins"
#     service: "github"
#     repo: "matryer/bitbar-plugins"
#     username: "your-github-username-not-your-email"
#     app_password: "personal-access-token"
#
# should_monitor_on_weekends: true

###### END_CONFIG

SERVICES = {
  bitbucket: {
    api_prefix: "https://api.bitbucket.org/2.0/repositories",
    api_suffix: "pullrequests",
    human_prefix: "https://bitbucket.org",
    human_suffix: "pull-requests"
  },
  github: {
    api_prefix: "https://api.github.com/repos",
    api_suffix: "pulls?state=open&type=pr",
    human_prefix: "https://github.com",
    human_suffix: "pulls"
  }
}.freeze

require "net/http"
require "net/https"
require "json"
require "base64"
require "yaml"

$color_black   = "\e[30m"
$color_red     = "\e[31m"
$color_green   = "\e[32m"
$color_yellow  = "\e[33m"
$color_blue    = "\e[34m"
$color_cyan    = "\e[36m"
$color_white   = "\e[37m"
$color_bg_blue = "\e[44m"
$color_bg_white= "\e[47m"
$color_bg_gray = "\e[40m"
$ansi_clear    = "\e[0m"

class GetPullRequests
  def do_it!
    return if $PROGRAM_NAME != __FILE__
    parse_yaml_config
    if !should_monitor_on_weekends? && its_a_weekend?
      # puts "  | font=DejaVuSansMonoNerdFontCompleteM-Book" # PR
      return
    end

    retrieve_pr_counts
  end

  private

  def should_monitor_on_weekends?
    @should_monitor_on_weekends
  end

  def its_a_weekend?
    now = Time.now
    now.saturday? || now.sunday?
  end

  def called_by_bitbar?
    $PROGRAM_NAME =~ /bitbar/i
  end

  def parse_yaml_config
    if !File.exist? REPOS_YAML
      puts "Configure #{__dir__}/configs/repos.yaml. See source for example."
      exit
    end
    config = YAML.load_file REPOS_YAML
    @should_monitor_on_weekends = config["should_monitor_on_weekends"] || false
    @global_username = config["username"] || nil
    @global_app_password = config["app_password"] || nil

    @repos = []
    config["repos"].each do |repo|
      repo_hash = { name: repo["name"], service: repo["service"], repo: repo["repo"] }
      repo_hash[:username] = @global_username if !@global_username.nil?
      repo_hash[:username] = repo["username"] if !repo["username"].nil?
      repo_hash[:app_password] = @global_app_password if !@global_app_password.nil?
      repo_hash[:app_password] = repo["app_password"] if !repo["app_password"].nil?
      @repos << repo_hash
    end
  end

  def call_api(http_method, endpoint, token = nil)
    uri = URI endpoint

    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP.const_get(http_method.downcase.capitalize).new(uri)
      request.add_field "Authorization", "token #{token}" if !token.nil?
      request.add_field "Content-Type", "application/json"
      response = http.request(request)
      yield(response)
    rescue StandardError => error
      puts "? " # PR
      if called_by_bitbar?
        puts "---"
        puts "Got Error: #{error.message}"
      end
    end
  end

  def retrieve_pr_counts
    total_pr_count = 0
    repo_details = ["---"]

    @repos.each do |repo|
      if repo[:app_password]
        token = Base64.encode64("#{repo[:username]}:#{repo[:app_password]}").chomp if repo[:service] == "bitbucket"
        token = repo[:app_password] if repo[:service] == "github"
      end

      service = SERVICES[repo[:service].to_sym]
      endpoint = "#{service[:api_prefix]}/#{repo[:repo]}/#{service[:api_suffix]}"
      human_url = "#{service[:human_prefix]}/#{repo[:repo]}/#{service[:human_suffix]}"

      call_api 'GET', endpoint, token do |response|
        pr_count = pr_count_for_bitbucket(response) if repo[:service] == "bitbucket"
        pr_count = pr_count_for_github(response) if repo[:service] == "github"
        total_pr_count += pr_count

        pr_count_str = "- #{pr_count}"
        repo_details << "#{repo[:name]} #{pr_count > 0 ? pr_count_str : ''}| #{pr_count == 0 ? 'color=#28a745': ''} href=#{human_url}" if called_by_bitbar?
        pr_details = pr_details_for_github(response) if repo[:service] == "github"
        repo_details.concat pr_details
      end
    end

    if total_pr_count.positive?
      puts "#{$color_white}#{total_pr_count} #{$ansi_clear} | ansi=true size=16 font=DejaVuSansMonoNerdFontCompleteM-Book" # PR
    else
      puts called_by_bitbar? ? "#{$color_green} #{$color_blue}#{$ansi_clear} | ansi=true size=12 font=DejaVuSansMonoNerdFontCompleteM-Book" : " " # PR
    end
    puts repo_details.join("\n") if called_by_bitbar?
  end

  def pr_count_for_github(response)
    links = {}
    if response["Link"]
      header_links = response["Link"].split(',')
      header_links.each do |link|
        (page, rel) = link.match(/&page=(.*)>; rel="(.*)"/).captures
        links[rel] = page
      end
      links["last"].to_i
    else
      result = JSON.parse(response.body)
      result.count.to_i
    end
  end

  def pr_count_for_bitbucket(response)
    result = JSON.parse(response.body)
    result["size"].to_i
  end

  def pr_details_for_github(response)
    result = []
    pr_details = JSON.parse(response.body)
    pr_details.each do |pr_detail|
      result << "--#{$color_cyan}#{pr_detail['title']}#{$ansi_clear} ##{pr_detail['number']} | href=#{pr_detail['html_url']}"
      result << "--#{$color_blue}#{pr_detail['head']['ref']}#{$ansi_clear} #{$color_yellow}@#{pr_detail['user']['login']}#{$ansi_clear} | ansi=true size=12 href=#{pr_detail['html_url']}/files"
      result << "-----"
    end
    result
  end
end

GetPullRequests.new.do_it!
