require 'observer'
require 'rubygems'
require 'memcache'

# @note simple wrapper around functions provided my the memcache gem 
class MemCacheClient
  include Observable
 
  @@MEMCACHE_STORED = "STORED\r\n"
  @@MEMCACHE_EXISTS = "EXISTS\r\n"
  @@MEMCACHE_DELETED = "DELETED\r\n"

  # @param [String] hostname 
  def initialize hostname 
    @hashInTheSky = MemCache.new hostname
  end

  # @param [Object] key
  # @return [Object, nil] value
  def get key
    @hashInTheSky.get( key )
  end

  # @param [Object] key
  # @return [Boolean] success
  def delete key
    begin
      status = @hashInTheSky.delete( key )
      if status == @@MEMCACHE_DELETED
        return true
      else
        return false
      end
    rescue MemCache::MemCacheError => e
      log "There has been an error deleting the key #{key}:\n#{e.message}\n#{e.backtrace.inspect}"
      return false
    end    
  end

  # @param [Object] key
  # @param [Object] value
  # @return [Boolean] success
  def set key, value
    begin
      status = @hashInTheSky.set( key, value )
      if status == @@MEMCACHE_STORED
        log "#{key} has been successfully set."
        return true
      else
        log "Setting the key #{key} to #{value} expected to return '#{@@MEMCACHE_STORED}', got #{status}"
        return false
      end
    rescue MemCache::MemCacheError => e
      log "There has been an error setting the key #{key} to #{value}:\n#{e.message}\n#{e.backtrace.inspect}"
      return false
    end
  end

  # @note makes sure that the value is set.
  #   Retries if necessary, with the value returned by the given block
  # @param [Object] key
  # @param [Object] value
  # @param [Proc] retry block, optional
  # @return [Boolean] success 
  def cas key, value, block = nil
    begin
      status = @hashInTheSky.cas( key ) do |val|
        val = value
      end
    
      if status == @@MEMCACHE_STORED
        log "#{key} has been successfully set."
        return true
      elsif status == @@MEMCACHE_EXISTS
        log "#{key} has been changed since the last fetch."
        if block
          log "Retrying"
          value = get( key )
          newValue = block.call( value )
          cas( key, newValue )
        else
          log "#{key} has been changed since last time and has not been updated."
          return false
        end
      elsif status.nil?
        log "#{key} does not exist. Creating and storing the given value."
        set( key, value ) 
      end
      
      rescue MemCache::MemCacheError => e
        log "There has been an error Checking and Setting #{key}:\n#{e.inspect}"
        return false
    end
  end

  # @note assumes that the value behind the key is an Array
  # @param [String] key
  # @return [Object, nil, Boolean] value
  def pop key
    sendTo key, :pop
  end

  # @note assumes the value behind the key is an Array, strips the first element from it
  # @param [Object] key
  # @return [Object, nil, Boolean]
  def shift key
    sendTo key, :shift
  end

  # @note attempts to invoke an arbitraty method on a value, saves the subject of the operation
  #   meant for streamlining Array operations
  # @param [Object] key
  # @param [Symbol] methodName
  # @param [*Object] any number of arguments
  # @return [Object, nil, Boolean] result of the operation
  def sendTo key, method, *args
    begin
      status = nil 
      until status == @@MEMCACHE_STORED
        log "Attempting to call #{method.to_s} on the value of #{key}"
        arrayValue = get key || []
        
        element = arrayValue.send method, *args
         
        status = @hashInTheSky.cas( key ) do |val|
          val = arrayValue
        end
      end
      log "Called #{method.to_s} on the value of #{key}"
      return element
    rescue MemCache::MemCacheError => e
      log "There has been an error calling #{method.to_s} on #{key}\n#{e.inspect}"
      return false
    end

  end

  # @note writes a formatted log message to a file
  # @param [String] message  
  def log message
    sourcedMessage = "[MemCache] #{message}"

    changed
    notify_observers sourcedMessage 
  end

  # @note delegates methods to MemCache
  #   I'm purposefully not using the Forwardable module here because I want to use my own error handling
  #   Plus, the performance hit that follows method_missing use is minimized by overwriting the methods I use most frequently
  # @param [String] methodName
  # @param [Object] arguments
  def method_missing name, *args
    begin
      @hashInTheSky.send name.to_sym, args
    rescue MemCache::MemCacheError => e
      log "There has been a MemCache error calling a method '#{name}' on '#{@hashInTheSky}:\n#{e.message}\n#{e.backtrace.inspect}"
    rescue Exception => e
      log "Exception caught while calling a method '#{name}] on '#{@hashInTheSky}':\n#{e.message}\n#{e.backtrace.inspect}"
    end
  end

end
