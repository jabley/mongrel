require 'mongrel'


module Mongrel
  # Support for the Camping micro framework at http://camping.rubyforge.org
  # This implements the unusually long Postamble that Camping usually
  # needs and shrinks it down to just a single line or two.
  #
  # Your Postamble would now be:
  #
  #   Mongrel::Camping::start("0.0.0.0",3001,"/tepee",Tepee).join
  #
  # If you wish to get fancier than this then you can use the
  # Camping::CampingHandler directly instead and do your own
  # wiring:
  #
  #   h = Mongrel::HttpServer.new(server, port)
  #   h.register(uri, CampingHandler.new(Tepee))
  #   h.register("/favicon.ico", Mongrel::Error404Handler.new(""))
  #
  # I add the /favicon.ico since camping apps typically don't 
  # have them and it's just annoying anyway.
  module Camping

    # This is a specialized handler for Camping applications
    # that has them process the request and then translates
    # the results into something the Mongrel::HttpResponse
    # needs.
    class CampingHandler < Mongrel::HttpHandler
      def initialize(klass)
        @klass = klass
      end

      def process(request, response)
        req = StringIO.new(request.body)
        controller = @klass.run(req, request.params)
        response.start(controller.status) do |head,out|
          controller.headers.each do |k, v|
            [*v].each do |vi|
              head[k] = vi
            end
          end
          out << controller.body
        end
      end
    end

    # This is a convenience method that wires up a CampingHandler
    # for your application on a given port and uri.  It's pretty
    # much all you need for a camping application to work right.
    #
    # It returns the Mongrel::HttpServer which you should either
    # join or somehow manage.  The thread is running when 
    # returned.

    def Camping.start(server, port, uri, klass)
      h = Mongrel::HttpServer.new(server, port)
      h.register(uri, CampingHandler.new(klass))
      h.register("/favicon.ico", Mongrel::Error404Handler.new(""))
      h.run
      return h
    end
  end
end
