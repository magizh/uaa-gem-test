#--
# Cloud Foundry 2012.02.03 Beta
# Copyright (c) [2009-2012] VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache License, Version 2.0 (the "License").
# You may not use this product except in compliance with the License.
#
# This product includes a number of subcomponents with
# separate copyright notices and license terms. Your use of these
# subcomponents is subject to the terms and conditions of the
# subcomponent's license, as noted in the LICENSE file.
#++

require 'cli/base'
require 'cli/config'

module CF::UAA

class CommonCli < Topic

  def trace?; opts[:trace] end
  def debug?; opts[:debug] end

  def auth_header
    unless (ttype = Config.value(:token_type)) && (token = Config.value(:access_token))
      raise "Need an access token to complete this command. Please login."
    end
    "#{ttype} #{token}"
  end

  def username(name); name || ask("User name") end
  def userpwd(pwd = opts[:password]); pwd || ask_pwd("Password") end
  def clientname(name = opts[:client]); name || ask("Client name") end
  def clientsecret(name = opts[:secret]); name || ask_pwd("Client secret") end

  def verified_pwd(prompt, pwd = nil)
    while pwd.nil?
      pwd_a = ask_pwd prompt
      pwd_b = ask_pwd "Verify #{prompt.downcase}"
      pwd = pwd_a if pwd_a == pwd_b
    end
    pwd
  end

  def askd(prompt, defary)
    return ask(prompt) unless defary
    result = ask("#{prompt} [#{Util.strlist(defary)}]")
    result.nil? || result.empty? ? defary : result
  end

  def complain(e)
    case e
    when TargetError then gripe "\n#{e.message}:\n#{JSON.pretty_generate(e.info)}"
    when Exception
      gripe "\n#{e.class}: #{e.message}"
      gripe e.backtrace if trace?
    when String then gripe e
    else gripe "unknown type of gripe: #{e.class}, #{e}"
    end
  end

  def handle_request
    yield
  rescue Exception => e
    complain e
  end

  def update_target_info(info = nil)
    return if !info && Config.target_value(:prompts)
    info ||= Misc.server(Config.target)
    Config.target_opts(prompts: info[:prompts])
    Config.target_opts(token_endpoint: info[:token_endpoint]) if info[:token_endpoint]
    info
  end

end

class MiscCli < CommonCli

  topic "Miscellaneous", "misc"

  desc "version", "Display version" do
    say "UAA client #{VERSION}"
  end

  define_option :trace, "--[no-]trace", "-t", "display extra verbose debug information"
  define_option :debug, "--[no-]debug", "-d", "display debug information"
  define_option :help, "--[no-]help", "-h", "display helpful information"
  define_option :version, "--[no-]version", "-v", "show version"
  define_option :config, "--config [string|file]", "file to get/save configuration information or yaml string"

  desc "help [topic|command...]", "Display summary or details of command or topic" do |*args|
    # handle hidden command, output commands in form for bash completion
    return say_commands if args.length == 1 && args[0] == "commands"
    args.empty? ? say_help : say_command_help(args)
  end

  def normalize_url(url, scheme = nil)
    url = url.strip.gsub(/\/*$/, "")
    raise ArgumentError, "invalid whitespace in target url" if url =~ /\s/
    unless url =~ /^https?:\/\//
      return unless scheme
      url = "#{scheme}://#{url}"
    end
    url = URI.parse(url)
    url.host.downcase!
    url.to_s.to_sym
  end

  def bad_uaa_url(url, info)
    info.replace(Misc.server(url.to_s))
    nil
  rescue Exception => e
    "failed to access #{url}: #{e.message}"
  end

  define_option :force, "--[no-]force", "-f", "set context even if target UAA is not available"
  desc "target [uaa_url]", "Display current or set new target", :force do |uaa_url|
    msg, info = nil, {}
    if uaa_url
      if uaa_url.to_i.to_s == uaa_url
        return gripe "invalid target index" unless url = Config.target?(uaa_url.to_i)
      elsif url = normalize_url(uaa_url)
        return gripe msg if (msg = bad_uaa_url(url, info)) unless opts[:force] || Config.target?(url)
      elsif !Config.target?(url = normalize_url(uaa_url, "https")) &&
            !Config.target?(url = normalize_url(uaa_url, "http"))
        if opts[:force]
          url = normalize_url(uaa_url, "https")
        elsif bad_uaa_url((url = normalize_url(uaa_url, "https")), info)
          return gripe msg if msg = bad_uaa_url((url = normalize_url(uaa_url, "http")), info)
        end
      end
      Config.target = url # we now have a canonical url set to https if possible
      update_target_info(info) if info[:prompts]
    end
    return say "no target set" unless Config.target
    return say "target set to #{Config.target}" unless Config.context
    say "target set to #{Config.target}, with context #{Config.context}"
  end

  desc "targets", "Display all targets" do
    cfg = Config.config
    return say "\nno targets\n" if cfg.empty?
    cfg.each_with_index { |(k, v), i| pp "#{i} #{v[:current] ? '*' : ' '} #{k}" }
    say "\n"
  end

  def config_pp(tgt = nil, ctx = nil)
    Config.config.each_with_index do |(k, v), i|
      next if tgt && tgt != k
      say ""
      splat = v[:current] ? '*' : ' '
      pp "[#{i}]#{splat}[#{k}]"
      v.each { |tk, tv| pp tv, 2, terminal_columns, tk unless tk == :contexts }
      next unless v[:contexts]
      v[:contexts].each_with_index do |(sk, sv), si|
        next if ctx && ctx != sk
        say ""
        splat = sv[:current] && v[:current]? '*' : ' '
        sv.delete(:current)
        pp "[#{si}]#{splat}[#{sk}]", 2
        pp sv, 4
      end
    end
    say ""
  end

  desc "context [name]", "Display or set current context" do |ctx|
    ctx = ctx.to_i if ctx.to_i.to_s == ctx
    Config.context = ctx if ctx && Config.valid_context(ctx)
    (opts[:trace] ? Config.add_opts(trace: true) : Config.delete_attr(:trace)) if opts.key?(:trace)
    return say "no context set in target #{Config.target}" unless Config.context
    config_pp Config.target, Config.context
  end

  desc "contexts", "Display all contexts" do config_pp end

end

end
