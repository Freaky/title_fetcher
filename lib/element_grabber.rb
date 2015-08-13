
require 'set'

require 'charlock_holmes'
require 'http'
require 'mojibake'
require 'oga'

class ElementGrabber
	attr_reader :read_limit

	DEFAULT_READ_LIMIT    = 128 * 1024 # 128k
	BLOCK_SIZE            = 32 * 1024
	REDIRECTION_LIMIT     = 6
	ALLOWED_CONTENT_TYPES = %r{\A(?:text/|application/(?:xml|xhtml))}
	DEFAULT_TIMEOUTS      = { read: 10, write: 10, connect: 10 }
	DEFAULT_HEADERS       = {
		HTTP::Headers::USER_AGENT => self.name
	}

	def initialize(tag, read_limit: DEFAULT_READ_LIMIT, timeout: {}, headers: {})
		@tag        = tag
		@timeout    = timeout.merge(DEFAULT_TIMEOUTS)
		@read_limit = Integer(read_limit)

		@headers    = headers.merge(DEFAULT_HEADERS)
		@http_client = HTTP.timeout(@timeout).headers(@headers).accept(:html)

		@encoding_detector  = CharlockHolmes::EncodingDetector.new rescue CharlockHolmes::EncodingDetector
		@encoding_converter = CharlockHolmes::Converter
		@encoding_fixer     = MojiBake::Mapper.new
	end

	def from_url(url)
		content = nil

		return unless response = get_with_redirect(url)
		return unless ALLOWED_CONTENT_TYPES.match response.content_type.mime_type

		extractor = ElementExtractor.new(@tag) do |text|
			content = text
			throw :done
		end

		so_far = 0
		reader = Enumerator.new do |parser|
			while chunk = response.body.readpartial(BLOCK_SIZE)
				next if chunk.empty?

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

	def guess_encoding(text) @encoding_detector.detect(text) end

	def convert_encoding(text, encoding)
		converted = @encoding_converter.convert(text, encoding[:encoding], 'UTF-8')
		@encoding_fixer.recover(converted).scrub
	end

	STATUS_REDIRECT = [301, 302, 303, 307, 308].freeze # *glares at http.rb*

	def get_with_redirect(url, redirections = Set.new)
		response = get(url)
		return response if response.status.ok?

		if STATUS_REDIRECT.include? response.status.code and target = response['Location']
			if target.start_with?('/')
				uri = URI.parse(url)
				target = "#{uri.scheme}://#{uri.host}:#{uri.port}#{target}"
			end

			return unless redirections.add?(target) and redirections.size < REDIRECTION_LIMIT
			return get_with_redirect(target, redirections)
		end
	end

	def get(url)
		@http_client.get(url)
	end

	class ElementExtractor
		def initialize(element, &callback)
			@element  = element
			@callback = callback
			@inside   = 0
			@content  = []
		end

		def on_element(_namespace, name, _attrs)
			@inside += 1 if name.casecmp(@element).zero?
		end

		def after_element(_namespace, name)
			return unless inside? and name.casecmp(@element).zero?
			@callback.call(@content.join)
			@inside -= 1
		end

		def on_text(text) @content << text if inside? end

		def inside?() @inside > 0 end
	end
end
