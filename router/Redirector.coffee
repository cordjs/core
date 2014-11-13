define [
  "cord!router/#{if CORD_IS_BROWSER then 'clientSideRouter' else 'serverSideRouter'}"
], (router) ->

  class Redirector

    @inject: ['serverResponse']

    redirect: (path) ->
      if CORD_IS_BROWSER
        router.redirect(path)
      else
        router.redirect(path, @serverResponse)