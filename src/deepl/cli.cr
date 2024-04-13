require "../ext/crest"
require "deepl/translator"
require "term-spinner"
require "./parser"

module DeepL
  class CLI
    class_property debug : Bool = false
    getter parser : Parser
    getter option : Options

    def initialize
      @parser = DeepL::Parser.new
      @option = parser.parse(ARGV)
    end

    def run
      case option.action
      when Action::TranslateText
        translate_text
      when Action::TranslateDocument
        translate_document
      when Action::ListGlossaryLanguagePairs
        print_glossary_language_pairs
      when Action::CreateGlossary
        create_glossary
      when Action::DeleteGlossary
        delete_glossary
      when Action::ListGlossaries
        print_glossary_list
      when Action::ListGlossariesLong
        print_glossary_list_long
      when Action::OutputGlossaryEntries
        output_glossary_entries
      when Action::ListFromLanguages
        print_source_languages
      when Action::ListTargetLanguages
        print_target_languages
      when Action::RetrieveUsage
        print_usage
      when Action::Version
        print_version
      when Action::Help
        print_help
      else
        raise ArgumentError.new("Invalid action: #{option.action}")
      end
    rescue ex
      error_message = "[deepl-cli] ERROR: #{ex.class} #{ex.message}"
      error_message += "\n#{ex.response}" if ex.is_a?(Crest::RequestFailed)
      error_message += "\n#{ex.backtrace.join("\n")}" if CLI.debug
      STDERR.puts error_message
      exit(1)
    end

    private def with_spinner(&block)
      spinner = Term::Spinner.new(clear: true)
      spinner.run do
        block.call
      end
    end

    private def remove_ansi_escape_codes(text)
      # gsub(/\e\[[0-9;]*[mGKHF]/, "")
      # The above regular expression used to be used.
      # However, it is insufficient because it cannot remove bold and other characters.
      #
      # How can I remove the ANSI escape sequences from a string in python
      # https://stackoverflow.com/questions/14693701
      # Python regular expressions were converted for PCRE2 using ChatGPT.
      ansi_escape_8bit = Regex.new(
        "(?:\x1B[@-Z\\-_]|[\\x80-\\x9A\\x9C-\\x9F]|(?:\x1B\\[|\\x9B)[0-?]*[ -/]*[@-~])"
      )
      text.gsub(ansi_escape_8bit, "")
    end

    def translate_text
      if option.input_text.empty?
        option.input_text = ARGF.gets_to_end
      end

      # Remove ANSI escape codes from the input text
      option.input_text = remove_ansi_escape_codes(option.input_text)

      result = nil
      translator = DeepL::Translator.new

      with_spinner do
        result = translator.translate_text(
          text: option.input_text,
          target_lang: option.target_lang,
          source_lang: option.source_lang,
          formality: option.formality,
          glossary_name: option.glossary_name, # original option of deepl.cr
          context: option.context
        )
      end

      r = result.not_nil!
      result_text = r.text
      result_source_lang = r.detected_source_language

      if option.detect_source_lanuage
        STDERR.puts "[deepl-cli] Detected source language: #{result_source_lang}"
      end
      puts result.not_nil!.text
    end

    def translate_document
      raise "Invalid option: -i --input" unless option.input_text.empty?
      raise "Input file is not specified" if ARGV.empty?
      option.input_path = Path[ARGV.shift]
      case ARGV.size
      when 1
        STDERR.puts "[deepl-cli] File #{ARGV[0]} is ignored"
      when 2..
        STDERR.puts "[deepl-cli] Files #{ARGV.join(", ")} are ignored"
      end

      translator = DeepL::Translator.new

      with_spinner do
        translator.translate_document(
          path: option.input_path,
          target_lang: option.target_lang,
          source_lang: option.source_lang,
          formality: option.formality,
          glossary_name: option.glossary_name, # original option of deepl.cr
          output_format: option.output_format,
          output_file: option.output_file,
          interval: option.interval
        ) do |progress|
          STDERR.puts avoid_spinner(progress)
        end
      end
    end

    def print_glossary_language_pairs
      translator = DeepL::Translator.new
      previous_source_lang = ""
      pairs = translator.get_glossary_language_pairs
      puts "Supported glossary language pairs"
      pairs.each do |pair|
        source_lang = pair.source_lang
        target_lang = pair.target_lang
        if source_lang != previous_source_lang
          puts if previous_source_lang != ""
          print "- #{source_lang} :\t"
          previous_source_lang = source_lang
        end
        print " #{target_lang}"
      end
      puts
    end

    def create_glossary
      # FIXME check TSV file format

      entry_format = "tsv"

      # A corner case still not handled:
      # Standard input is CSV file format

      if option.glossary_name.nil? && ARGV.size == 1
        name = ARGV[0]
        entry_format = File.extname(name).sub(".", "").downcase
        name = File.basename(name, File.extname(name))
        option.glossary_name = name
      end
      option.input_text = ARGF.gets_to_end

      translator = DeepL::Translator.new
      translator.create_glossary(
        name: option.glossary_name,
        source_lang: option.source_lang,
        target_lang: option.target_lang,
        entries: option.input_text,
        entry_format: entry_format
      )

      STDERR.puts "[deepl-cli] Glossary #{option.glossary_name} is created"
    end

    def delete_glossary
      translator = DeepL::Translator.new
      if ARGV.size == 0
        print_help
        exit(1)
      else
        glossary_name = ARGV[0]
        translator.delete_glossary_by_name(glossary_name)
      end

      STDERR.puts "[deepl-cli] Glossary #{glossary_name} is deleted"
    end

    def output_glossary_entries
      translator = DeepL::Translator.new
      output_file = option.output_file
      if ARGV.size == 0
        print_help
        exit(1)
      else
        glossary_name = ARGV[0]
        entries_text = translator.get_glossary_entries_by_name(glossary_name)
      end
      if output_file
        File.write(output_file, entries_text)
        STDERR.puts "[deepl-cli] Glossary entries are written to #{output_file}"
      else
        puts entries_text
      end
    end

    def print_glossary_list
      translator = DeepL::Translator.new
      glossary_list = translator.list_glossaries
      return if glossary_list.empty?
      glossary_list.each do |glossary|
        puts glossary.name
      end
    end

    def print_glossary_list_long
      translator = DeepL::Translator.new
      glossary_list = translator.list_glossaries
      return if glossary_list.empty?
      max = glossary_list.map { |g| g.name.size }.max.not_nil!
      glossary_list.each do |glossary|
        puts [
          glossary.name.rjust(max + 1),
          "#{glossary.source_lang} -> #{glossary.target_lang}",
          glossary.entry_count,
          glossary.creation_time,
          glossary.glossary_id,
        ].join("\t")
      end
    end

    def print_source_languages
      translator = DeepL::Translator.new
      langinfo = translator.get_source_languages
      print_langinfo(langinfo)
    end

    def print_target_languages
      translator = DeepL::Translator.new
      langinfo = translator.get_target_languages
      default_target_language = translator.guess_target_language
      print_langinfo(langinfo, default: default_target_language)
    end

    private def print_langinfo(
      langinfo : Array(LanguageInfo),
      default : String? = nil
    ) : Nil
      langinfo.each do |info|
        abbrev = info.language
        name = info.name
        formality = info.supports_formality
        row = String.build { |s|
          s << ((default && (default == abbrev)) ? "+ " : "- ")
          s << "#{abbrev.ljust(7)}#{name.ljust(24)}"
          s << "supports formality" if formality
        }
        puts row
      end
    end

    def print_usage
      translator = DeepL::Translator.new
      puts translator.server_url
      puts translator.get_usage.map { |k, v| "#{k}: #{v}" }.join("\n")
    end

    def print_version
      puts DeepL::CLI::VERSION
    end

    def print_help
      puts parser.help_message
    end

    private def avoid_spinner(str)
      return str unless STDERR.tty?
      "#{"\e[2K\r" if STDERR.tty?}" + str
    end
  end
end