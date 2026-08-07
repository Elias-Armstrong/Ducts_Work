# ===== Consolidated from: services/pipe_connection_service.rb =====
module DuctExtension
  module Services
    module PipeTargetConnectionService
      def self.insert_smart_tee_target(
        model:,
        network:,
        target_pipe_piece:,
        click_point:,
        active_start_point:,
        active_start_port: nil,
        active_dimensions: nil,
        requested_branch_direction: nil
      )
        return nil unless model && network
        return nil unless target_pipe_piece
        return nil unless target_pipe_piece.type == :pipe
        return nil unless target_pipe_piece.ports && target_pipe_piece.ports.length == 2
        return nil unless click_point && active_start_point

        port_a = target_pipe_piece.ports[0]
        port_b = target_pipe_piece.ports[1]
        dimensions = Model::Port.dimensions_from_params({}, port_a)

        requested_branch_dimensions =
          if active_start_port
            Model::Port.dimensions_from_params({}, active_start_port)
          elsif active_dimensions
            Model::DuctDimensions.coerce(active_dimensions, fallback: dimensions)
          else
            dimensions
          end

        placement = TeePlacementCalculator.best_placement(
          pipe_start: port_a.point,
          pipe_end: port_b.point,
          dimensions: dimensions,
          click_point: click_point,
          active_start_point: active_start_point,
          active_start_port: active_start_port,
          requested_branch_direction: requested_branch_direction,
          preferred_width_axis: port_a.width_axis || port_b.width_axis,
          preferred_height_axis: port_a.height_axis || port_b.height_axis
        )
        return nil unless placement

        TeeInsertService.insert_tee_on_pipe(
          model: model,
          network: network,
          pipe_piece: target_pipe_piece,
          tap_point: placement[:center],
          branch_direction: placement[:branch_vector],
          branch_dimensions: requested_branch_dimensions
        )
      rescue => error
        puts "PipeTargetConnectionService.insert_smart_tee_target failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end
    end
  end
end

# ===== Consolidated from: services/port_to_port_route_service.rb =====
module DuctExtension
  module Services
    class PortToPortRouteService
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

        dimensions = active_dimensions_for(
          start_port: start_port,
          target_port: target_port,
          shape: shape,
          diameter: diameter,
          width: width,
          height: height
        )

        target_dimensions = Model::Port.dimensions_from_params({}, target_port)
        transition_plan = passive_transition_plan(
          source_port: start_port,
          target_port: target_port,
          active_dimensions: dimensions,
          target_dimensions: target_dimensions
        )
        return nil unless transition_plan

        routing_target_port = transition_plan[:routing_target_port]
        passive_transition_step = transition_plan[:transition_step]

        unless start_port
          return connect_loose_point_to_port(
            model: model,
            network: network,
            source_point: start_point,
            target_port: target_port,
            routing_target_port: routing_target_port,
            dimensions: dimensions,
            passive_transition_step: passive_transition_step
          )
        end

        steps = route_steps(
          source_port: start_port,
          target_port: routing_target_port,
          dimensions: dimensions,
          fitting_mode: fitting_mode
        )
        return nil unless steps && !steps.empty?

        steps << passive_transition_step if passive_transition_step
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

      def self.connect_loose_point_to_port(
        model:,
        network:,
        source_point:,
        target_port:,
        routing_target_port:,
        dimensions:,
        passive_transition_step:
      )
        return nil unless routing_target_port && routing_target_port.point
        return nil if source_point.distance(routing_target_port.point) <= Routing::RouteMath::MIN_ROUTE_LENGTH

        steps = [
          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              start_point: source_point,
              end_point: routing_target_port.point
            )
          )
        ]

        steps << passive_transition_step if passive_transition_step

        build_steps_and_connect(
          model: model,
          network: network,
          target_port: target_port,
          steps: steps
        )
      end
      private_class_method :connect_loose_point_to_port

      # Once a route is attached to a real source port, that port is the
      # authoritative active size and shape. UI state may change while hovering
      # another fitting, but the active route must not silently adopt the passive
      # target's dimensions.
      def self.active_dimensions_for(start_port:, target_port:, shape:, diameter:, width:, height:)
        return start_port.dimensions if start_port && start_port.respond_to?(:dimensions)

        Model::Port.dimensions_from_params(
          { shape: shape, diameter: diameter, width: width, height: height },
          target_port
        )
      end
      private_class_method :active_dimensions_for

      def self.passive_transition_plan(
        source_port:,
        target_port:,
        active_dimensions:,
        target_dimensions:
      )
        unless passive_transition_needed?(active_dimensions, target_dimensions)
          return {
            routing_target_port: target_port,
            transition_step: nil
          }
        end

        transition_length = passive_transition_length(active_dimensions, target_dimensions)
        target_incoming_vector = Geometry::VectorMath.normalized(
          target_port.outward_vector.clone.reverse
        )

        return nil unless target_incoming_vector
        return nil unless transition_length > Routing::RouteMath::MIN_ROUTE_LENGTH

        # The transition occupies the final section immediately before the passive
        # target. The active route ends at a virtual port with its own dimensions;
        # the deferred transition then changes both size and, when necessary,
        # round/rectangular shape before connecting to the real target port.
        transition_start_point = target_port.point.offset(
          target_incoming_vector.clone.reverse,
          transition_length
        )

        routing_target_port = virtual_target_port_for_transition(
          source_port: source_port,
          target_port: target_port,
          point: transition_start_point,
          dimensions: active_dimensions
        )
        return nil unless routing_target_port

        target_is_rectangular = target_dimensions[:shape].to_sym == :rectangular

        transition_step = Model::BuildStep.new(
          :reducer,
          active_dimensions.merge(
            deferred_start: true,
            end_point: target_port.point,
            start_dimensions: active_dimensions,
            end_dimensions: target_dimensions,
            preferred_width_axis: target_is_rectangular ? target_port.width_axis : nil,
            preferred_height_axis: target_is_rectangular ? target_port.height_axis : nil
          )
        )

        {
          routing_target_port: routing_target_port,
          transition_step: transition_step
        }
      rescue => error
        puts "PortToPortRouteService.passive_transition_plan failed: #{error.message}"
        nil
      end
      private_class_method :passive_transition_plan

      def self.passive_transition_needed?(active_dimensions, target_dimensions)
        if defined?(BranchTransitionService) && BranchTransitionService.respond_to?(:transition_needed?)
          return BranchTransitionService.transition_needed?(
            active_dimensions,
            target_dimensions
          )
        end

        active = Model::DuctDimensions.coerce(active_dimensions)
        target = Model::DuctDimensions.coerce(target_dimensions)
        active.shape != target.shape || !active.same_size?(target)
      rescue
        false
      end
      private_class_method :passive_transition_needed?

      def self.passive_transition_length(active_dimensions, target_dimensions)
        if defined?(BranchTransitionService) && BranchTransitionService.respond_to?(:default_branch_length)
          BranchTransitionService.default_branch_length(active_dimensions, target_dimensions).to_f
        elsif defined?(Geometry::ReducerBuilder) && Geometry::ReducerBuilder.respond_to?(:default_length)
          Geometry::ReducerBuilder.default_length(active_dimensions, target_dimensions).to_f
        else
          [
            Model::DuctDimensions.coerce(active_dimensions).largest,
            Model::DuctDimensions.coerce(target_dimensions).largest
          ].max
        end
      rescue
        12.0
      end
      private_class_method :passive_transition_length

      def self.virtual_target_port_for_transition(
        source_port:,
        target_port:,
        point:,
        dimensions:
      )
        active = Model::DuctDimensions.coerce(dimensions)

        width_axis =
          if active.rectangular?
            (source_port && source_port.width_axis) || target_port.width_axis
          end

        height_axis =
          if active.rectangular?
            (source_port && source_port.height_axis) || target_port.height_axis
          end

        Model::Port.new(
          point: point,
          vector: target_port.outward_vector.clone,
          diameter: active.diameter,
          shape: active.shape,
          width: active.width,
          height: active.height,
          width_axis: width_axis,
          height_axis: height_axis,
          piece: target_port.piece
        )
      rescue
        nil
      end
      private_class_method :virtual_target_port_for_transition
    end
  end
end
