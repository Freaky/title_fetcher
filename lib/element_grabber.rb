#!/usr/bin/env ruby

require 'set'

require 'charlock_holmes'
require 'http'
require 'oga'

class ElementGrabber
	attr_reader :read_limit

	class ElementExtractor
		def initialize(element, &callback)
			@element  = element
			@callback = callback
			@inside   = 0
			@content  = []
		end

		def on_element(namespace, name, attrs = {})
			@inside += 1 if name.casecmp(@element).zero?
		end

		def after_element(namespace, name)
			return unless inside? and name.casecmp(@element).zero?
			@callback.call(@content.join)
			@inside -= 1
		end

		def on_text(text)
			@content << text if inside?
		end

		def inside?() @inside > 0 end
	end

	BLOCK_SIZE            = 32 * 1024
	REDIRECTION_LIMIT     = 6
	ALLOWED_SCHEMES       = %w(http https).freeze
	ALLOWED_CONTENT_TYPES = %r{\A(?:text/|application/(?:xml|xhtml))}

	def initialize(tag, read_limit: 128 * 1024)
		@tag = tag
		@read_limit = Integer(read_limit)
		@encoding_detector = CharlockHolmes::EncodingDetector.new
	end

	def from_url(url, redirections = Set.new)
		content = nil
		return unless ALLOWED_SCHEMES.include? URI.parse(url).scheme

		return unless response = get_with_redirect(url)
		return unless ALLOWED_CONTENT_TYPES.match response.content_type.mime_type

		extractor = ElementExtractor.new(@tag) do |text|
			content = text
			throw :done
		end

		so_far = 0
		reader = Enumerator.new do |parser|
			detected_encoding = nil
			encoding_converter = nil

			while chunk = (response.body.readpartial(BLOCK_SIZE))
				so_far += chunk.size
				detected_encoding ||= guess_encoding(chunk)
				parser << convert_encoding(chunk, detected_encoding)

				if so_far > read_limit
					response.body.close
					throw :done
				end
			end
		end

		catch(:done) do
			Oga.sax_parse_html(extractor, reader)
		end

		return content
	rescue => e
		warn("Exception processing #{url}: #{e.class}, #{e.message}, #{e.backtrace.join("\n")}")
		return content
	end

	def guess_encoding(text)
		@encoding_detector.detect(text)
	end

	def convert_encoding(text, encoding)
		CharlockHolmes::Converter.convert(text, encoding[:encoding], 'UTF-8')
	end

	def get_with_redirect(url, redirections = Set.new)
		response = HTTP.get(url)

		case response.status.code
		when 301, 302, 303, 307, 308
			target = response['Location']
			return nil if target.nil? or target.empty?

			if target.start_with?('/')
				uri = URI.parse(url)
				target = "#{uri.scheme}://#{uri.host}:#{uri.port}#{target}"
			end

			return if redirections.include?(target)
			return if redirections.size > REDIRECTION_LIMIT
			redirections << target

			return get_with_redirect(target, redirections)
		else return response if response.status.ok?
		end
	end
end
