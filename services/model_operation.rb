module DuctExtension
  module Services
    # Coordinates a SketchUp operation with the in-memory duct graph. If an
    # operation aborts after mutating Network, the graph is rebuilt in-place
    # from the rolled-back model so callers do not keep stale topology objects.
    #
    # Most callers should use .run. Interactive tools can call start!, commit!,
    # and rollback! so a mouse drag remains one SketchUp undo operation.
    class ModelOperation
      class Abort < StandardError
        attr_reader :result

        def initialize(result = nil)
          @result = result
          super("Duct model operation aborted")
        end
      end

      attr_reader :model, :network, :name

      def self.run(model:, network:, name:, validate: nil, rebuild_on_failure: true)
        operation = new(
          model: model,
          network: network,
          name: name,
          validate: validate,
          rebuild_on_failure: rebuild_on_failure
        )
        operation.run { |context| yield(context) }
      end

      def initialize(model:, network:, name:, validate: nil, rebuild_on_failure: true)
        @model = model
        @network = network
        @name = name
        @validate = validate
        @rebuild_on_failure = rebuild_on_failure
        @started = false
        @finished = false
      end

      def run
        start!
        result = yield(self)
        commit!(result)
      rescue Abort => abort_signal
        rollback!
        abort_signal.result
      rescue Exception
        rollback!
        raise
      end

      # Begin a long-lived operation. Used by interactive drags that span
      # several SketchUp Tool callbacks.
      def start!
        return self if @started && !@finished
        raise "Model operation already finished" if @finished

        @model.start_operation(@name, true)
        @started = true
        self
      end

      # Finish a previously-started operation and make the Ruby graph agree
      # with the final SketchUp geometry before committing the undo step.
      def commit!(result = nil)
        return result if @finished
        start! unless @started

        finalize_network!
        validate_network! if validation_enabled?

        @model.commit_operation
        @finished = true
        result
      rescue Exception
        rollback!
        raise
      end

      # Abort a started operation and reconstruct the in-memory network from
      # the rolled-back SketchUp model. Safe to call more than once.
      def rollback!
        return if @finished

        abort_operation!
        recover_network! if @rebuild_on_failure
        nil
      end

      def abort!(result = nil)
        raise Abort, result
      end

      def finalize_network!
        @network.rebuild_index! if @network && @network.respond_to?(:rebuild_index!)
      end

      private

      def validation_enabled?
        return @validate unless @validate.nil?

        DuctExtension.respond_to?(:network_validation_enabled?) &&
          DuctExtension.network_validation_enabled?
      end

      def validate_network!
        NetworkValidator.validate!(@network)
      end

      def abort_operation!
        return unless @started
        return if @finished

        @model.abort_operation
        @finished = true
      rescue => error
        puts "ModelOperation abort failed for #{@name}: #{error.message}"
      end

      def recover_network!
        return unless @model && @network

        NetworkRebuildService.rebuild(@model, target_network: @network)
      rescue => error
        puts "ModelOperation network recovery failed for #{@name}: #{error.message}"
        puts error.backtrace.join("\n")
      end
    end
  end
end
