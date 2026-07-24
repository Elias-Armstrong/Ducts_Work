module DuctExtension
  module Services
    class PortToPortRouteService
      # Compatibility constants retained for callers that may reference them.
      MIN_ROUTE_LENGTH = Routing::RouteMath::MIN_ROUTE_LENGTH
      DIRECTION_MATCH_DOT = Routing::RouteMath::DIRECTION_MATCH_DOT
      TARGET_ALIGNMENT_DOT = Routing::RouteMath::TARGET_ALIGNMENT_DOT
      DEFAULT_BEND_RADIUS_FACTOR = Routing::RouteMath::DEFAULT_BEND_RADIUS_FACTOR
      TWO_TERMINAL_MISS_TOLERANCE = Routing::RouteMath::TWO_TERMINAL_MISS_TOLERANCE

      def self.connect(
        model:,
        network:,
        source_port:,
        source_point:,
        target_port:,
        diameter:,
        shape: :round,
        width: nil,
        height: nil,
        fitting_mode: :elbow
      )
        return nil unless model && network && target_port

        start_port = source_port
        start_point = start_port ? start_port.point : source_point
        return nil unless start_point
        return nil if start_port && start_port == target_port

        dimensions = Model::Port.dimensions_from_params(
          { shape: shape, diameter: diameter, width: width, height: height },
          start_port || target_port
        )

        unless start_port
          return connect_loose_point_to_port(
            model: model,
            network: network,
            source_point: start_point,
            target_port: target_port,
            dimensions: dimensions
          )
        end

        target_dimensions = Model::Port.dimensions_from_params({}, target_port)
        routing_target_port = target_port
        passive_reducer_step = nil

        if passive_reducer_needed?(dimensions, target_dimensions)
          reducer_length = passive_reducer_length(dimensions, target_dimensions)
          target_incoming_vector = Geometry::VectorMath.normalized(target_port.outward_vector.clone.reverse)

          if target_incoming_vector && reducer_length > MIN_ROUTE_LENGTH
            # Preserve the existing port-vector convention used by the working
            # passive-reducer implementation.
            reducer_start_point = target_port.point.offset(target_incoming_vector.clone.reverse, reducer_length)
            routing_target_port = virtual_target_port_for_reducer(
              target_port: target_port,
              point: reducer_start_point,
              dimensions: dimensions
            )

            passive_reducer_step = Model::BuildStep.new(
              :reducer,
              dimensions.merge(
                deferred_start: true,
                end_point: target_port.point,
                start_dimensions: dimensions,
                end_dimensions: target_dimensions,
                preferred_width_axis: target_port.width_axis,
                preferred_height_axis: target_port.height_axis
              )
            )
          end
        end

        steps = route_steps(
          source_port: start_port,
          target_port: routing_target_port,
          dimensions: dimensions,
          fitting_mode: fitting_mode
        )
        return nil unless steps && !steps.empty?

        steps << passive_reducer_step if passive_reducer_step
        build_steps_and_connect(
          model: model,
          network: network,
          target_port: target_port,
          steps: steps
        )
      rescue => error
        puts "PortToPortRouteService.connect failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.route_steps(source_port:, target_port:, dimensions:, fitting_mode: :elbow)
        context = Routing::RouteContext.new(
          source_port: source_port,
          target_port: target_port,
          dimensions: dimensions,
          fitting_mode: fitting_mode
        )
        Routing::StrategyPipeline.steps(context)
      rescue => error
        puts "PortToPortRouteService.route_steps failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.build_steps_and_connect(model:, network:, target_port:, steps:)
        return nil unless steps && !steps.empty?

        GeometryExecutor.execute(
          model,
          steps,
          network,
          connect_target_port: target_port
        )
      end
      private_class_method :build_steps_and_connect

      def self.connect_loose_point_to_port(model:, network:, source_point:, target_port:, dimensions:)
        steps = [
          Model::BuildStep.new(
            :pipe,
            dimensions.merge(start_point: source_point, end_point: target_port.point)
          )
        ]

        build_steps_and_connect(
          model: model,
          network: network,
          target_port: target_port,
          steps: steps
        )
      end
      private_class_method :connect_loose_point_to_port

      def self.passive_reducer_needed?(active_dimensions, target_dimensions)
        active = Model::DuctDimensions.coerce(active_dimensions)
        target = Model::DuctDimensions.coerce(target_dimensions)
        active.shape == target.shape && !active.same_size?(target)
      rescue
        false
      end
      private_class_method :passive_reducer_needed?

      def self.passive_reducer_length(active_dimensions, target_dimensions)
        if defined?(Geometry::ReducerBuilder) && Geometry::ReducerBuilder.respond_to?(:default_length)
          Geometry::ReducerBuilder.default_length(active_dimensions, target_dimensions).to_f
        else
          [
            Model::DuctDimensions.coerce(active_dimensions).largest,
            Model::DuctDimensions.coerce(target_dimensions).largest
          ].max * 2.1
        end
      rescue
        12.0
      end
      private_class_method :passive_reducer_length

      def self.virtual_target_port_for_reducer(target_port:, point:, dimensions:)
        Model::Port.new(
          point: point,
          vector: target_port.outward_vector.clone,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: target_port.width_axis,
          height_axis: target_port.height_axis,
          piece: target_port.piece
        )
      rescue
        nil
      end
      private_class_method :virtual_target_port_for_reducer
    end
  end
end
