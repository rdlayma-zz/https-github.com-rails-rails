module ActionDispatch
  class Request
    # Access the contents of the flash. Use <tt>flash["notice"]</tt> to
    # read a notice you put there or <tt>flash["notice"] = "hello"</tt>
    # to put a new one.
    def flash
      @env[Flash::KEY] ||= Flash::FlashHash.from_session_value(session["flash"])
    end
  end

  # The flash provides a way to pass temporary objects between actions. Anything you place in the flash will be exposed
  # to the very next action and then cleared out. This is a great way of doing notices and alerts, such as a create
  # action that sets <tt>flash[:notice] = "Post successfully created"</tt> before redirecting to a display action that can
  # then expose the flash to its template. Actually, that exposure is automatically done. Example:
  #
  #   class PostsController < ActionController::Base
  #     def create
  #       # save post
  #       flash[:notice] = "Post successfully created"
  #       redirect_to posts_path(@post)
  #     end
  #
  #     def show
  #       # doesn't need to assign the flash notice to the template, that's done automatically
  #     end
  #   end
  #
  #   show.html.erb
  #     <% if flash[:notice] %>
  #       <div class="notice"><%= flash[:notice] %></div>
  #     <% end %>
  #
  # Since the +notice+ and +alert+ keys are a common idiom, convenience accessors are available:
  #
  #   flash.alert = "You must be logged in"
  #   flash.notice = "Post successfully created"
  #
  # This example just places a string in the flash, but you can put any object in there. And of course, you can put as
  # many as you like at a time too. Just remember: They'll be gone by the time the next action has been performed.
  #
  # See docs on the FlashHash class for more details about the flash.
  class Flash
    KEY = 'action_dispatch.request.flash_hash'.freeze

    class FlashNow #:nodoc:
      def initialize(flash)
        @flash = flash
      end

      def []=(k, v)
        @flash[k] = v
        @flash.discard(k)
        v
      end

      def [](k)
        @flash[k]
      end

      # Convenience accessor for flash.now[:alert]=
      def alert=(message)
        self[:alert] = message
      end

      # Convenience accessor for flash.now[:notice]=
      def notice=(message)
        self[:notice] = message
      end
    end

    class FlashHash < Hash
      def self.from_session_value(value)
        flash = case value
                when FlashHash # Before https://github.com/github/github-rails/pull/9
                  value
                when Hash # After, read plain Hash from the session
                  flashes = value['flashes'] || {}
                  flashes.stringify_keys!
                  discard = value['discard'] || []
                  discard = discard.map do |item|
                    item.kind_of?(Symbol) ? item.to_s : item
                  end
                  new_from_values(flashes, Set.new(discard))
                else
                  new
                end
        flash.tap(&:sweep)
      end

      def to_session_value
        return nil if empty?
        {'discard' => @used.to_a, 'flashes' => Hash[to_a]}
      end

      def initialize #:nodoc:
        super
        @used = Set.new()
      end

      def []=(k, v) #:nodoc:
        k = k.to_s
        keep(k)
        super(k, v)
      end

      def [](k)
        super(k.to_s)
      end

      def delete(k)
        super(k.to_s)
      end

      def update(h) #:nodoc:
        h.stringify_keys!
        h.keys.each { |k| keep(k) }
        super(h)
      end

      alias :merge! :update

      def replace(h) #:nodoc:
        @used = Set.new
        super(h.stringify_keys)
      end

      # Sets a flash that will not be available to the next action, only to the current.
      #
      #     flash.now[:message] = "Hello current action"
      #
      # This method enables you to use the flash as a central messaging system in your app.
      # When you need to pass an object to the next action, you use the standard flash assign (<tt>[]=</tt>).
      # When you need to pass an object to the current action, you use <tt>now</tt>, and your object will
      # vanish when the current action is done.
      #
      # Entries set via <tt>now</tt> are accessed the same way as standard entries: <tt>flash['my-key']</tt>.
      def now
        FlashNow.new(self)
      end

      # Keeps either the entire current flash or a specific flash entry available for the next action:
      #
      #    flash.keep            # keeps the entire flash
      #    flash.keep(:notice)   # keeps only the "notice" entry, the rest of the flash is discarded
      def keep(k = nil)
        use(k, false)
      end

      # Marks the entire flash or a single flash entry to be discarded by the end of the current action:
      #
      #     flash.discard              # discard the entire flash at the end of the current action
      #     flash.discard(:warning)    # discard only the "warning" entry at the end of the current action
      def discard(k = nil)
        use(k)
      end

      # Mark for removal entries that were kept, and delete unkept ones.
      #
      # This method is called automatically by filters, so you generally don't need to care about it.
      def sweep #:nodoc:
        keys.each do |k|
          unless @used.include?(k)
            @used << k
          else
            delete(k)
            @used.delete(k)
          end
        end

        # clean up after keys that could have been left over by calling reject! or shift on the flash
        (@used - keys).each{ |k| @used.delete(k) }
      end

      # Convenience accessor for flash[:alert]
      def alert
        self[:alert]
      end

      # Convenience accessor for flash[:alert]=
      def alert=(message)
        self[:alert] = message
      end

      # Convenience accessor for flash[:notice]
      def notice
        self[:notice]
      end

      # Convenience accessor for flash[:notice]=
      def notice=(message)
        self[:notice] = message
      end

      private
        # Used internally by the <tt>keep</tt> and <tt>discard</tt> methods
        #     use()               # marks the entire flash as used
        #     use('msg')          # marks the "msg" entry as used
        #     use(nil, false)     # marks the entire flash as unused (keeps it around for one more action)
        #     use('msg', false)   # marks the "msg" entry as unused (keeps it around for one more action)
        # Returns the single value for the key you asked to be marked (un)used or the FlashHash itself
        # if no key is passed.
        def use(key = nil, used = true)
          Array(key || keys).each { |k| used ? @used << k : @used.delete(k) }
          return key ? self[key] : self
        end

        def self.new_from_values(flashes, used)
          new.tap do |flash_hash|
            flashes.each do |k, v|
              flash_hash[k] = v
            end
            flash_hash.instance_variable_set("@used", used)
          end
        end
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    ensure
      session    = env['rack.session'] || {}
      flash_hash = env[KEY]

      if flash_hash
        if !flash_hash.empty? || session.key?('flash')
          session["flash"] = flash_hash.to_session_value
          new_hash = flash_hash.dup
        else
          new_hash = flash_hash
        end

        env[KEY] = new_hash
      end

      if session.key?('flash') && session['flash'].nil?
        session.delete('flash')
      end
    end
  end
end
