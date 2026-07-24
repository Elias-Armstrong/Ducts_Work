module DuctExtension
  module Services
    module Routing
      class RouteContext
        attr_reader :source_port, :target_port, :dimensions, :fitting_mode
        attr_reader :source_vector, :target_incoming_vector

        def initialize(source_port:, target_port:, dimensions:, fitting_mode: :elbow)
          @source_port = source_port
          @target_port = target_port
          @dimensions = Model::DuctDimensions.coerce(dimensions)
          @fitting_mode = fitting_mode.to_sym
          @source_vector = Geometry::VectorMath.normalized(source_port&.outward_vector)
          @target_incoming_vector = Geometry::VectorMath.normalized(target_port&.outward_vector&.clone&.reverse)
        end

        def valid?
          !!(@source_port && @target_port && @source_vector && @target_incoming_vector)
        end

        def straight_only?
          @fitting_mode == :straight
        end

        def start_point
          @source_port.point
        end

        def target_point
          @target_port.point
        end
      end
    end
  end
end
