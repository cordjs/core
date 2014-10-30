define [
  'bcryptjs'
], (bcryptjs) ->

  class PasswordEncoder

    @encode: (password, encoderAlgo, encoderSalt, encoderClentSalt, encoderOptions) ->
      if encoderAlgo == 'bcrypt'
        encoder = @encodeBcrypt
      else
        throw new Error("Unsupported crypt algorithm '" + encoderAlgo + "' in passwordEncode()!")
      encode = encoder(password, encoderSalt, encoderOptions)
      encoder(encode, encoderClentSalt, encoderOptions)


    @encodeBcrypt: (data, salt, options) ->
      if not options.cost
        throw new Error("'cost' option is required for passwordBcryptEncode() call!")
      cost = options.cost
      if cost < 10
        cost = "0" + cost
      salt = "$2y$" + cost + "$" + salt
      bcryptjs.hashSync(data, salt)