MemCacheClient
==============

I couldn't introduce new gems into a legacy codebase, so I rolled my own MemCache convenience library

Used for a small task that expects 3 concurrent instances

Like this:

require 'MemCacheClient'

def update message
  #do something with status messages
end

hashInTheSky = MemCacheClient.new 'memcacheaddress:11211'

value = hashInTheSky.get( 'key' )

updateOperation = lambda do |value|
  value = value + 1
end

updatedValue = updateOperation.call( value )

hashInTheSky.cas 'key', updatedValue, updatedOperation


Looks unusual with the lambda, but it allows to encapsulate the retry logic,
so that you could 'fire and forget' your memcache operations
