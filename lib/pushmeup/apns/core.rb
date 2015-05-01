require 'socket'
require 'openssl'
require 'json'

module APNS
  @applications = []
  @host = 'gateway.sandbox.push.apple.com'
  @port = 2195
  # openssl pkcs12 -in mycert.p12 -out client-cert.pem -nodes -clcerts
  # @pem = nil # this should be the path of the pem file not the contentes
  # @pass = nil
  
  @persistent = false
  @mutex = Mutex.new
  @retries = 3 # TODO: check if we really need this
  
  @connections = []
  # @sock = nil
  # @ssl = nil
  
  class << self
    attr_accessor :applications, :host, :port#, :pem, :pass
  end
  
  def self.start_persistence
    @persistent = true
  end
  
  def self.stop_persistence
    @persistent = false
    @connections.each do |connection|
      connection[:ssl].close
      connection[:sock].close
    end
  end
  
  def self.send_notification(device_token, message, application=nil)
    n = APNS::Notification.new(device_token, message)
    self.send_notifications([n], application)
  end
  
  def self.send_notifications(notifications, application=nil)
    @mutex.synchronize do
      self.with_connection do
        notifications.each do |n|
          name_connection = @connections.select{|connection| connection[:application] == application }.first
          name_connection[:ssl].write(n.packaged_notification)
        end
      end
    end
  end
  
  def self.feedback
    connections = self.feedback_connection

    connections.map do |connection|
      apns_feedback = []
      while line = connection[:ssl].read(38)   # Read lines from the socket
        line.strip!
        f = line.unpack('N1n1H140')
        apns_feedback << { :timestamp => Time.at(f[0]), :token => f[2] }
      end

      connection[:ssl].close
      connection[:sock].close

      return apns_feedback
    end
  end
  
protected
  
  def self.with_connection
    attempts = 1
    
    begin
      # If no @ssl is created or if @ssl is closed we need to start it
      if @connections.length == 0 #|| @ssl.nil? || @sock.nil? || @ssl.closed? || @sock.closed?
        @connections = self.open_connections
      end
    
      yield
    
    rescue StandardError, Errno::EPIPE
      raise unless attempts < @retries

      @connections.each do |connection|
        connection[:ssl].close
        connection[:sock].close
      
        attempts += 1
      end
      retry
    end
  
    # Only force close if not persistent
    unless @persistent
      @connections.each do |connection|
        connection[:ssl].close
        connection[:sock].close
      end
      @connections = []
    end
  end
  
  def self.open_connections
    return self.applications.map do |application|
      raise "The path to your pem file is not set. (APNS.pem = /path/to/cert.pem)" unless application[:pem]
      raise "The path to your pem file does not exist!" unless File.exist?(application[:pem])
      
      context      = OpenSSL::SSL::SSLContext.new
      context.cert = OpenSSL::X509::Certificate.new(File.read(application[:pem]))
      context.key  = OpenSSL::PKey::RSA.new(File.read(application[:pem]), application[:pass])

      sock         = TCPSocket.new(application[:host], application[:port])
      ssl          = OpenSSL::SSL::SSLSocket.new(sock,context)
      ssl.connect
      {sock: sock, ssl: ssl, application: application[:application]}
    end
  end
  
  def self.feedback_connection
    return self.applications.map do |application|
      raise "The path to your pem file is not set. (APNS.pem = /path/to/cert.pem)" unless application[:pem]
      raise "The path to your pem file does not exist!" unless File.exist?(application[:pem])
      
      context      = OpenSSL::SSL::SSLContext.new
      context.cert = OpenSSL::X509::Certificate.new(File.read(application[:pem]))
      context.key  = OpenSSL::PKey::RSA.new(File.read(application[:pem]), application[:pass])

      fhost = self.application.gsub('gateway','feedback')

      sock         = TCPSocket.new(fhost, 2196)
      ssl          = OpenSSL::SSL::SSLSocket.new(sock,context)
      ssl.connect
      {sock: sock, ssl: ssl, application: application[:application]}
    end
  end
end
