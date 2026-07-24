module DuctExtension
  module Geometry
    module CrossBuilder
      SOCKET_DEPTH_FACTOR = 0.82

      HUB_MAIN_RADIUS_FACTOR = 0.60
      HUB_SIDE_RADIUS_FACTOR = 0.56
      HUB_NORMAL_RADIUS_FACTOR = 0.52

      HUB_SEGMENTS = 18
      HUB_RINGS = 8

      RECTANGULAR_OVERLAP = 0.04
      RECTANGULAR_SEAM_HIDE_PADDING = 0.12

      def self.socket_depth(diameter_or_width, height = nil)
        if height
          [diameter_or_width.to_f, height.to_f].max * SOCKET_DEPTH_FACTOR
        else
          diameter_or_width.to_f * SOCKET_DEPTH_FACTOR
        end
      end

      def self.build_into(
        group,
        center,
        forward_vector,
        side_vector,
        diameter: nil,
        width: nil,
        height: nil,
        shape: :round,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        branch_diameter: nil,
        branch_width: nil,
        branch_height: nil
      )
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        forward_vector = RectangularFrame.normalized(forward_vector)
        side_vector = RectangularFrame.normalized(side_vector)

        return false unless center && forward_vector && side_vector
        return false if forward_vector.parallel?(side_vector)

        if shape == :rectangular
          build_rectangular(
            group: group,
            center: center,
            forward_vector: forward_vector,
            side_vector: side_vector,
            width: width.to_f,
            height: height.to_f,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis,
            branch_width: branch_width,
            branch_height: branch_height
          )
        else
          build_round(
            group: group,
            center: center,
            forward_vector: forward_vector,
            side_vector: side_vector,
            diameter: diameter.to_f,
            branch_diameter: branch_diameter
          )
        end
      rescue => error
        puts "CrossBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

    end
  end
end
require_relative 'cross/round_geometry'
require_relative 'cross/rectangular_geometry'
require_relative 'cross/shared_geometry'
