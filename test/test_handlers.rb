# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://mongrel.rubyforge.org/attributions.html 
# for more information.

require 'test/testhelp'

class SimpleHandler < Mongrel::HttpHandler
  def process(request, response)
    response.start do |head,out|
      head["Content-Type"] = "text/html"
      results = "<html><body>Your request:<br /><pre>#{request.params.to_yaml}</pre><a href=\"/files\">View the files.</a></body></html>"
      out << results
    end
  end
end

class DumbHandler < Mongrel::HttpHandler
  def process(request, response)
    response.start do |head,out|
      head["Content-Type"] = "text/html"
      out.write("test")
    end
  end
end

def check_status(results, expecting)
  results.each do |res|
    assert(res.kind_of?(expecting), "Didn't get #{expecting}, got: #{res.class}")
  end
end

class HandlersTest < Test::Unit::TestCase

  def setup
    @port = process_based_port
    stats = Mongrel::StatisticsFilter.new(:sample_rate => 1)

    @config = Mongrel::Configurator.new :host => '127.0.0.1', :port => @port do
      listener do
        uri "/", :handler => SimpleHandler.new
        uri "/", :handler => stats
        uri "/404", :handler => Mongrel::Error404Handler.new("Not found")
        uri "/dumb", :handler => Mongrel::DeflateFilter.new
        uri "/dumb", :handler => DumbHandler.new, :in_front => true
        uri "/files", :handler => Mongrel::DirHandler.new("doc")
        uri "/files_nodir", :handler => Mongrel::DirHandler.new("doc", listing_allowed=false, index_html="none")
        uri "/status", :handler => Mongrel::StatusHandler.new(:stats_filter => stats)
        uri "/relative", :handler => Mongrel::DirHandler.new(nil, listing_allowed=false, index_html="none")
      end
    end

    @test_file = windows? ? "testfile" : "tmp/testfile"

    File.open("/#{@test_file}", 'w') do
      # Do nothing
    end

    @config.run
  end

  def teardown
    @config.stop(false, true)
    File.delete "/#{@test_file}"
  end

  def test_more_web_server
    res = hit([ "http://localhost:#{@port}/test",
          "http://localhost:#{@port}/dumb",
          "http://localhost:#{@port}/404",
          "http://localhost:#{@port}/files/rdoc/index.html",
          "http://localhost:#{@port}/files/rdoc/nothere.html",
          "http://localhost:#{@port}/files/rdoc/",
          "http://localhost:#{@port}/files_nodir/rdoc/",
          "http://localhost:#{@port}/status",
    ])
    check_status res, String
  end

  def test_nil_dirhandler
    # Camping uses this internally
    handler = Mongrel::DirHandler.new(nil, false)
    assert handler.can_serve("/#{@test_file}")
    # Not a bug! A nil @file parameter is the only circumstance under which
    # we are allowed to serve any existing file
    assert handler.can_serve("../../../../../../../../../../#{@test_file}")
  end
  
  def test_non_nil_dirhandler_is_not_vulnerable_to_path_traversal
    # The famous security bug of Mongrel 1.1.2
    handler = Mongrel::DirHandler.new("/doc", false)
    assert_nil handler.can_serve("/#{@test_file}")
    assert_nil handler.can_serve("../../../../../../../../../../#{@test_file}")
  end

  def test_deflate
    Net::HTTP.start("localhost", @port) do |h|
      # Test that no accept-encoding returns a non-deflated response
      req = h.get("/dumb")
      assert(
        !req['Content-Encoding'] ||
        !req['Content-Encoding'].include?('deflate'))
      assert_equal "test", req.body

      req = h.get("/dumb", {"Accept-Encoding" => "deflate"})
      # -MAX_WBITS stops zlib from looking for a zlib header
      inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
      assert req['Content-Encoding'].include?('deflate')
      assert_equal "test", inflater.inflate(req.body)
    end
  end

  # TODO: find out why this fails on win32 but nowhere else
  #def test_posting_fails_dirhandler
  #  req = Net::HTTP::Post.new("http://localhost:#{@port}/files/rdoc/")
  #  req.set_form_data({'from'=>'2005-01-01', 'to'=>'2005-03-31'}, ';')
  #  res = hit [["http://localhost:#{@port}/files/rdoc/",req]]
  #  check_status res, Net::HTTPNotFound
  #end

  def test_unregister
    @config.listeners["127.0.0.1:#{@port}"].unregister("/")
  end
end

