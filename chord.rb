#!/usr/bin/env ruby

require 'eventmachine'
require 'securerandom'
require 'optparse'
require 'ostruct'

class Chord
  BITS = 8
end

# Represents the local or remote node
class Node
  class << self
    def get(id)

    end
  end

  attr_accessor :id, :host, :port

  def initialize(id, host, port, connection = nil)
    @id = id
    @host = host
    @port = port

    @connection = EventMachine.connect(host, port, NodeConnection)
  end

  # This is the messaging implementation
  # The dht protocol is implemented in the Client class
  def find_successor(id, closure)
    # Send successor message to node and return answer
    puts "--- asking #{@host}:#{@port} SUCCESSOR of #{id}"

    request = "REQ SUCCESSOR #{id}\n"

    @connection.request = request
    @connection.closure = closure
    @connection.send_data(request)
  end

  def predecessor(closure)
    # Asks the node what is its predecessor
    puts "--- asking #{@host}:#{@port} PREDECESSOR"

    request = "REQ PREDECESSOR\n"

    @connection.request = request
    @connection.closure = closure
    @connection.send_data(request)
  end

  def notify(id, node)
    # Notifies the node we're its predecessor
    puts "--- sending #{@host}:#{@port} NOTIFY #{id}"

    request = "REQ NOTIFY #{id} #{node.host}:#{node.port}\n"

    @connection.request = request
    @connection.send_data(request)
  end
end

class NodeConnection < EventMachine::Connection
  attr_accessor :request, :closure

  def receive_data(data)
    puts "--- node received data: #{data.strip!}"

    if(data =~ /^!OK\sSUCCESSOR\s(\d+)\s(\w+):(\d+)/)
      @closure.call(Node.new($1.to_i, $2, $3.to_i)) unless @closure.nil?
    end

    if(data =~ /^!OK\sPREDECESSOR\s(\d+)\s(\w+):(\d+)/)
      @closure.call(Node.new($1.to_i, $2, $3.to_i)) unless @closure.nil?
    end

    if(data =~ /^!OK\sNOTIFY/)
    end
  end

  def unbind()
    puts "--- node connection unbound"
  end
end

class Client
  attr_accessor :successor, :predecessor

  def initialize(options = OpenStruct.new)
    # This key is for testing purposes only
    if(options.host)
      id = SecureRandom.random_number(2**Chord::BITS)
    else
      id = 0
    end

    @next = 0
    @node_cache = {}

    # Creating a "server" to listen for incoming requests
    # The EVENT LOOP
    EventMachine.run {
      EventMachine.threadpool_size = 200

      # Creating this client's node object
      @node = Node.new(id, "localhost", 10000 + id)
      @node_cache[id] = @node

      # While another client doesn't join a ring, this is pretty much true
      @predecessor = @node
      @successor = @node

      # Creating this client's finger table with the known succesors
      # (which, until we join something or be joined by someone, is
      # always this node itself, so ronery, sosad)
      @finger = Chord::BITS.times.map do |i|
        @node
      end

      EventMachine.start_server(@node.host, @node.port, ClientConnection) do |con|
        con.client = self
      end

      puts "--- client listening on #{@node.host}:#{@node.port}"
      #puts "Client finger: #{@finger}"

      if(options.host)
        host = options.host.split(/:/).first
        port = options.host.split(/:/).last.to_i
        connection = EventMachine.connect(host, port, NodeConnection)
        node = Node.new(nil, host, port, connection)

        join(node)
      end

      faster = EventMachine::PeriodicTimer.new(1) do
        fix_fingers()
      end

      timer = EventMachine::PeriodicTimer.new(5) do
        stabilize()
        #check_predecessor()

        puts ">>> #{@successor.id}"
        puts "=== #{@node.id}"
        puts "<<< #{@predecessor.id unless @predecessor.nil?}"
      end
    }
  end

  def find_successor(id, closure = nil)
    if(in_range?(id, @node.id, @successor.id))
      closure.call(@successor) unless closure.nil?
    else
      closure ||= lambda { |res| puts res }
      closest_preceding_node(id).find_successor(id, closure)
    end
  end

  def closest_preceding_node(id)
    Chord::BITS.downto(1).each do |i|
      if(in_range?(@finger[i-1].id, @node.id, id, true, true))
        return @finger[i-1]
      end
    end

    return @node
  end

  def stabilize()
    closure = lambda { |res|
      node = res

      if(in_range?(node.id, @node.id, @successor.id, true, true))
        @successor = node
      end

      @successor.notify(@node.id, @node)
    }

    if(@successor.eql?(@node))
      closure.call(@predecessor)
    else
      @successor.predecessor(closure)
    end
  end

  def notify(node)
    if(@predecessor.nil? or in_range?(node.id, @predecessor.id, @node.id, true, true))
      @predecessor = node
    end
  end

  def fix_fingers()
    @next = 0 if(@next >= Chord::BITS)

    closure = lambda { |res|
      puts "--- find successor #{@node.id + (2**(@next))}: #{res.id}"
      @finger[@next] = res
      @next = @next + 1
     }

    find_successor(@node.id + (2**(@next)), closure)
  end

  def check_predecessor()
    puts "--- checking predecessor for connectivity"
  end

  def join(node)
    @predecessor = nil

    predecessor_closure = lambda { |res|
      @predecessor = res
      @successor.notify(@node.id, @node)
    }

    successor_closure = lambda { |res|
      @successor = res
      @successor.predecessor(predecessor_closure)
    }

    node.find_successor(@node.id, successor_closure)
  end

  #######
  private
  #######

  def in_range?(key, lower, upper, begin_open = true, end_open = false)
    # TODO: fix this: open interval
    lower = lower + 1 if begin_open
    upper = upper - 1 if end_open

    if(lower <= upper)
      return ((lower..upper) === key)
    else
      return ((lower..(2**Chord::BITS - 1)) === key or (0..upper) === key)
    end
  end
end

class ClientConnection < EventMachine::Connection
  attr_accessor :client

  def connection_completed()
    puts "--- client connected!"
  end

  def receive_data(data)
    puts "--- received data: #{data.strip!}"

    if(data =~ /^REQ\sSUCCESSOR\s(\d+)/)
      closure = lambda { |res|
        reply = "!OK SUCCESSOR #{res.id} #{res.host}:#{res.port}\n"
        send_data(reply)
      }

      @client.find_successor($1.to_i, closure)
    end

    if(data =~ /^REQ\sPREDECESSOR/)
      reply = "!OK PREDECESSOR #{@client.predecessor.id} #{@client.predecessor.host}:#{@client.predecessor.port}\n"
      send_data(reply)
    end

    if(data =~ /^REQ\sNOTIFY\s(\d+)\s(\w+):(\d+)/)
      @client.notify(Node.new($1.to_i, $2, $3.to_i))

      reply = "!OK NOTIFY\n"
      send_data(reply)
    end
  end

  def unbind
    puts "--- client disconnected!"
  end
end

# Tests
options = OpenStruct.new

OptionParser.new do |opts|
  opts.banner = "Usage: chord.rb [options]"

  opts.on("-j HOST", "--join HOST", String, "One node of the DHT to join (format: host:port)") do |h|
    options.host = h
  end
end.parse!

c = Client.new(options)
