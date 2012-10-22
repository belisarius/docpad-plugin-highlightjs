module.exports = (BasePlugin) ->
	# Requires
	jsdom = require('jsdom')
	balUtil = require('bal-util')
	hljs = require('highlight.js')
	cache = {}

	# Define Plugin
	class HighlightjsPlugin extends BasePlugin
		# Plugin name
		name: 'highlightjs'

		# Plugin configuration
		config:
			replaceTab: null
			sourceFilter: null
			escape: false
			removeIndentation: false
			aliases:
				coffee: 'coffeescript'
				rb: 'ruby'
				js: 'javascript'

		# Get a JSDOM Window
		# next(err,window)
		getWindow: (next) ->
			# Create window
			if @window?
				next(null,@window)
			else
				jsdom.env(
					html: "<html><body></body></html>"
					features:
						QuerySelector: false
						MutationEvents: false
					done: (err,window) =>
						return next(err)  if err
						@window = window
						return next(null,window)
				)

			# Chain
			@

		isPreOrCode: (element) ->
			return false  unless element.tagName
			return element.tagName in ['PRE','CODE']

		findLanguage: (element) ->
			classes = element.className

			# No highlighting
			return 'no-highlight'  if /no[-]?highlight/i.test(classes)

			# Get all of the matching classes
			matches = classes.match(/lang(?:uage)?-\w+/g)
			# Return the last listed language class
			return matches.pop().match(/lang(?:uage)?-(\w+)/)[1] if matches

			# Auto-highlighting
			return ''

		# Highlight an element
		highlightElement: (opts) ->
			# Prepare
			{element,next} = opts
			config = balUtil.extend({},@config,opts.config)
			{escape,replaceTab,aliases,sourceFilter,removeIndentation} = config

			# Is the element's code wrapped inside a child node?
			childNode = element
			while childNode.hasChildNodes() and @isPreOrCode(childNode.childNodes[0])
				childNode = childNode.childNodes[0]

			# Is the element's code wrapped in a parent node?
			parentNode = childNode
			while @isPreOrCode(parentNode.parentNode)
				parentNode = parentNode.parentNode

			# Skip if the element is already highlighted
			return next(null,element.innerHTML)  if parentNode.className.indexOf('highlighted') isnt -1

			# Grab the source code
			source = childNode.innerHTML
			source = balUtil.removeIndentation(source)  if removeIndentation isnt false

			# Discover the language
			language = childNode.getAttribute('lang') or parentNode.getAttribute('lang')
			language = language.trim() or @findLanguage(childNode) or @findLanguage(parentNode)

			# Highlight
			if language isnt 'no-highlight'
				# Correctly escape the source
				if escape isnt true
					# Unescape the output as highlightjs always escape
					source = source.replace(/&amp;/gm, '&').replace(/&lt;/gm, '<').replace(/&gt;/gm, '>')

				# If a source filter is configured, run it
				if sourceFilter?
					if sourceFilter instanceof Function
						# sourceFilter = (source) ->
						source = sourceFilter(source, language)
					else if sourceFilter instanceof Array and sourceFilter.length is 2
						# sourceFilter = ['find' or RegExp, 'replace']
						source = source.replace(sourceFilter[0], sourceFilter[1])

				hljs.fixMarkup(source, replaceTab)  if replaceTab

				# Highlight
				language = language.toLowerCase()
				try
					# Correct aliases
					if language and aliases[language]
						language = aliases[language]

					# Perform the render
					if language and hljs.LANGUAGES[language]?
						result = hljs.highlight(language, source)
					else
						result = hljs.highlightAuto(source)

					# Extract the result
					language = result.language
					result = result.value
				catch err
					return next(err)  if err
			else
				result = source

			# Handle
			result = """
				<pre class="highlighted"><code class="#{language}">#{result}</code></pre>
				"""
			next(null,result)

			# Chain
			@

		# Render the document
		renderDocument: (opts, next) ->
			{extension,file} = opts
			plugin = @

			# Handle
			if file.type is 'document' and extension is 'html'
				# Check cache
				cacheKey = opts.content+file.attributes.plugins?.highlightjs
				cacheResult = cache[cacheKey]
				if cacheResult
					opts.content = cacheResult
					return next()

				# Get the window
				@getWindow (err,window) ->
					return next(err)  if err

					# Turn the code blocks into a JSDOM tree
					replaceElementCallback = (outerHTML, elementNameMatched, attributes, innerHTML, replaceElementCompleteCallback) ->
						# Create the element
						element = window.document.createElement('div')
						element.innerHTML = outerHTML

						# Highlight the element
						plugin.highlightElement(
							window: window
							element: element
							config: file.attributes.plugins?.highlightjs
							next: replaceElementCompleteCallback
						)

					# Grab all the code blocks
					balUtil.replaceElementAsync opts.content, '(?:code|pre)', replaceElementCallback, (err,result) ->
						return next(err)  if err
						opts.content = result
						cache[cacheKey] = result
						return next()
			else
				return next()
