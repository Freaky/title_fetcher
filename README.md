# TitleFetcher - Robust web title tag fetcher

TitleFetcher fetches title elements from websites.

  require 'titlefetcher'

  tf = TitleFetcher.new
  tf.fetch "http://freshbsd.org" # => "FreshBSD - The latest BSD Commits"

It tries to guess charset and converts/scrubs to UTF-8, making some effort
to correct common Mojibake issues.

Default timeouts for socket operations are 10 seconds, and it gives up
searching a document for title tags after the first 128KiB.  Documents
with content-types other than `text/*` and `application/{xml,xhtml}` are
not scanned.

TitleFetcher objects are expected to be safe to share across threads.

## Dependencies

 * Ruby 2.0+
 * charlock_holmes(-jruby)
 * mojibake
 * http.rb
 * oga

## TODO

 * Stricter per-request timeout.
 * Factor in HTTP and HTML headers to charset detection.
 * HEAD request to check Content-Type without inviting a bunch of other data.
 * Fall back to searching for h1 tags or so.
 * Tests.
 * Documentation.
 * Release as a gem.
 * Use it in something.

