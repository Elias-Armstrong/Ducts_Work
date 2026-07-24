module DuctExtension
  module Services
    # Coordinates a SketchUp operation with the in-memory duct graph. If an
    # operation aborts after mutating Network, the graph is rebuilt in-place
    # from the rolled-back model so callers do not keep stale topology objects.
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
        @model.start_operation(@name, true)
        @started = true

        result = yield(self)

        finalize_network!
        validate_network! if validation_enabled?

        @model.commit_operation
        @finished = true
        result
      rescue Abort => abort_signal
        abort_operation!
        recover_network! if @rebuild_on_failure
        abort_signal.result
      rescue Exception
        abort_operation!
        recover_network! if @rebuild_on_failure
        raise
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
