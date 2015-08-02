#!/usr/bin/env ruby

require 'set'

require 'charlock_holmes'
require 'httpclient'
require 'oga'

class ElementGrabber
	attr_reader :read_limit

	class ElementExtractor
		def initialize(element, &callback)
			@element = element
			@callback = callback
			@in_element = false
			@content = []
		end

		def on_element(namespace, name, attrs = {})
			if name == @element
				@in_element = true
			end
		end

		def after_element(namespace, name)
			if @in_element and name == @element
				@callback.call(@content.join)
			end
		end

		def on_text(text)
			if @in_element
				@content << text
			end
		end
	end

	BLOCK_SIZE        = 32 * 1024
	REDIRECTION_LIMIT = 6

	def initialize(tag, read_limit: 64 * 1024)
		@tag = tag
		@read_limit = Integer(read_limit)
		@encoding_detector = CharlockHolmes::EncodingDetector.new
	end

	def from_url(url, redirections = Set.new)
		content = nil
		client = HTTPClient.new
		request = client.get_async(url) #, {'Accept' => 'text/html; application/xml+xhtml'})
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

		reader = Enumerator.new do |parser|
			so_far = 0
			detected_encoding = nil
			encoding_converter = nil

			while chunk = response.content.readpartial(BLOCK_SIZE)
				unless detected_encoding
					detected_encoding = @encoding_detector.detect(chunk)
				end
				encoded_chunk = CharlockHolmes::Converter.convert(chunk, detected_encoding[:encoding], 'UTF-8')
				parser << encoded_chunk
				so_far += chunk.size

				if so_far > read_limit
					response.content.close
					throw :done
				end
			end
		end

		catch(:done) do
			Oga.sax_parse_html(extractor, reader)
		end

		return content
	rescue => e
		warn("Exception processing #{uri}: #{e.class}, #{e.message}, #{e.backtrace.join("\n")}")
		return content
	end
end
