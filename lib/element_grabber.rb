#!/usr/bin/env ruby

require 'set'

require 'charlock_holmes'
require 'httpclient'
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
			if inside? and name.casecmp(@element).zero?
				@callback.call(@content.join)
				@inside -= 1
			end
		end

		def on_text(text)
			@content << text if inside?
		end

		def inside?() @inside > 0 end
	end

	BLOCK_SIZE        = 32 * 1024
	REDIRECTION_LIMIT = 6
	ALLOWED_SCHEMES   = %w(http https).freeze

	def initialize(tag, read_limit: 128 * 1024)
		@tag = tag
		@read_limit = Integer(read_limit)
		@encoding_detector = CharlockHolmes::EncodingDetector.new
	end

	def from_url(url, redirections = Set.new)
		return unless ALLOWED_SCHEMES.include? URI.parse(url).scheme

		content = nil
		client = HTTPClient.new
		request = client.get_async(url)
		response = request.pop

		if response.redirect?
			target = response.headers['Location']
			return nil if target.nil? or target.empty?

			if target.start_with?('/')
				uri = URI.parse(url)
				target = "#{uri.scheme}://#{uri.host}:#{uri.port}#{target}"
			end

			return nil if redirections.include?(target) or redirections.size > REDIRECTION_LIMIT
			redirections << target

			return from_url(target, redirections)
		end

		return nil unless response.status == 200
		return nil if response.content_type !~ %r{\A(?:text/|application/(?:xml|xhtml))}

		extractor = ElementExtractor.new(@tag) do |text|
			content = text
			throw :done
		end

		so_far = 0
		reader = Enumerator.new do |parser|
			detected_encoding = nil
			encoding_converter = nil

			while chunk = (response.content.readpartial(BLOCK_SIZE) rescue nil)
				unless detected_encoding
					detected_encoding = @encoding_detector.detect(chunk)
				end
				so_far += chunk.size
				encoded_chunk = CharlockHolmes::Converter.convert(chunk, detected_encoding[:encoding], 'UTF-8')
				parser << encoded_chunk

				if so_far > read_limit
					response.content.close
					throw :done
				end
			end
		end

		catch(:done) do
			Oga.sax_parse_html(extractor, reader)
		end
		p "read #{so_far}"

		return content
	rescue => e
		warn("Exception processing #{uri}: #{e.class}, #{e.message}, #{e.backtrace.join("\n")}")
		return content
	end
end
