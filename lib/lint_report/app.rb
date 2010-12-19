# coding: utf-8

require "singleton"
require "open-uri"
require "trollop"
require "zlib"
require "fileutils"
require "ostruct"
require "thread"
require "gem_lint"

module LintReport
  class App
    include Singleton

    def self.run
      self.instance.run
    end

    def run
      verify_options
      start_workers
      download_new_gems
      while download_queue.size > 0
        sleep 0.5
      end
      remove_old_gems
      analyse_gems
    end

    private

    def verify_options
      if options[:output].nil?
        $stderr.puts "--output must be provided"
        exit 1
      end
      if options[:cachedir].nil?
        $stderr.puts "--cachedir must be provided"
        exit 1
      end
    end

    def download_queue
      @download_queue ||= SizedQueue.new(100)
    end

    def start_workers
      download_queue

      10.times do
        Thread.new do
          while item = download_queue.pop
            `wget -O #{item.path} #{item.url} > /dev/null 2>&1`
          end
        end
      end
    end

    def download_new_gems
      FileUtils.mkdir_p(cachedir)
      urls.each do |filename, url|
        path = File.join(cachedir, filename)
        if !File.file?(path) || File.size(path) == 0
          download_queue.push(OpenStruct.new(:url => url, :path => path))
        end
      end
      10.times do
        download_queue.push(:finished)
      end
    end

    def remove_old_gems
      FileUtils.mkdir_p(cachedir)
      Dir.entries(cachedir).each do |basename|
        if basename[0,1] != "." && !filenames.include?(basename)
          path = File.join(cachedir, basename)
          FileUtils.rm(path)
        end
      end
    end

    def analyse_gems
      File.open(output_file, "w") do |f|
        Dir.entries(cachedir).sort.each do |basename|
          if basename[0,1] != "."
            path = File.join(cachedir, basename)
            f.write(GemLint::Runner.new(path).to_s(:detailed) + "\n")
            f.flush
          end
        end
      end
    end

    def index
      data = Zlib::GzipReader.new(open("http://rubygems.org/latest_specs.4.8.gz")).read
      Marshal.load(data)
    end

    def filenames
      @filenames ||= index.map { |row|
        if row[2] == "ruby"
          "#{row[0]}-#{row[1]}.gem"
        else
          "#{row[0]}-#{row[1]}-#{row[2]}.gem"
        end
      }
    end

    def urls
      @urls ||= Hash[
        *filenames.zip(filenames.map { |f| "http://rubygems.org/downloads/#{f}"}).flatten
      ]
    end

    def cachedir
      @cachedir ||= File.expand_path(options[:cachedir])
    end

    def output_file
      @output_file ||= File.expand_path(options[:output])
    end

    def options
      @options ||= opts = Trollop::options do
        opt :output, "Output filename", :type => :string
        opt :cachedir, "Directory to cache downloaded gems", :type => :string
      end
    end

  end
end
