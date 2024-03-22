require "option_parser"
require "./options"
require "./translator"

module DeepL
  class Parser < OptionParser
    getter opt : Options
    getter translator : Translator

    def initialize(translator)
      super()
      @opt = Options.new
      @translator = translator
      self.banner = "Usage: deepl [options] <file>"
      # on("doc", "Upload and translate a document") do
      #   opt.sub_command = SubCmd::Document
      # end
      on("-i", "--input TEXT", "Input text") do |text|
        opt.input = text
      end
      on("-f", "--from [LANG]", "Source language [AUTO]") do |from|
        show_source_languages if from.empty?
        opt.source_lang = from.upcase
      end
      on("-t", "--to [LANG]", "Target language [EN]") do |to|
        show_target_languages if to.empty?
        opt.target_lang = to.upcase
      end
      on("-g ID", "--glossary ID", "Glossary ID") do |id|
        opt.glossary_id = id
      end
      on("-F", "--formality OPT", "Formality (default more less)") do |v|
        opt.formality = v
      end
      on("-C", "--context TEXT", "Context (experimental)") do |text|
        opt.context = text
      end
      on("-S", "--split-sentences OPT", "Split sentences") do |v|
        opt.split_sentences = v
      end
      on("-A", "--ansi", "Do not remove ANSI escape codes") do
        opt.no_ansi = false
      end
      on("-u", "--usage", "Check Usage and Limits") do
        show_usage
      end
      on("-d", "--debug", "Show backtrace on error") do
        DeepLError.debug = true
      end
      on("-v", "--version", "Show version") do
        show_version
      end
      on("-h", "--help", "Show this help") do
        show_help
      end
      invalid_option do |flag|
        STDERR.puts "[deepl-cli] ERROR: #{flag} is not a valid option."
        STDERR.puts self
        exit(1)
      end
    end

    def parse(args)
      super
      opt
    end

    def show_source_languages
      translator.source_languages.each do |lang|
        language, name = lang.values.map(&.to_s)
        puts "- #{language.ljust(7)}#{name}"
      end
      exit
    end

    def show_target_languages
      translator.target_languages.each do |lang|
        language, name, supports_formality = lang.values.map(&.to_s)
        formality = (supports_formality == "true") ? "YES" : "NO"
        puts "- #{language.ljust(7)}#{name.ljust(20)}\tformality support [#{formality}]"
      end
      exit
    end

    def show_usage
      puts translator.api_url_base
      puts translator.usage.map { |k, v| "#{k}: #{v}" }.join("\n")
      exit
    end

    def show_version
      puts DeepL::VERSION
      exit
    end

    def show_help
      puts self
      exit
    end
  end
end