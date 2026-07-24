module DuctExtension
  module Geometry
    module WyeBuilder
      SOCKET_DEPTH_FACTOR = 0.90
      BRANCH_ANGLE_DEGREES = 45.0

      RECTANGULAR_MAIN_EXTRA_FACTOR = 1.35
      ROUND_MAIN_EXTRA_FACTOR = 0.75
      RECTANGULAR_BRANCH_PULL_OUT_FACTOR = 1.25
      ROUND_BRANCH_PULL_OUT_FACTOR = 0.62
      RECTANGULAR_BRANCH_EXTRA_FACTOR = 1.25
      ROUND_BRANCH_EXTRA_FACTOR = 0.75

      ROUND_HUB_FORWARD_RADIUS_FACTOR = 0.86
      ROUND_HUB_SIDE_RADIUS_FACTOR = 0.70
      ROUND_HUB_NORMAL_RADIUS_FACTOR = 0.58
      ROUND_HUB_SEGMENTS = 24
      ROUND_HUB_RINGS = 10
      ROUND_INTERNAL_HIDE_RADIUS_FACTOR = 1.28
      ROUND_BRANCH_NECK_HIDE_FACTOR = 0.62

      RECTANGULAR_OPENING_CLEARANCE = 0.001
      RECTANGULAR_MIN_OPENING_SPAN_FACTOR = 0.38

      ROUND_BRANCH_SIDEWALL_OVERLAP_FACTOR = 0.88
      ROUND_BRANCH_VISIBLE_PROTRUSION_FACTOR = 1.65
      ROUND_BRANCH_SADDLE_WIDTH_FACTOR = 1.10
      ROUND_BRANCH_VISUAL_HIDE_RADIUS_FACTOR = 1.18
      ROUND_BRANCH_ENTRY_ARTIFACT_FORWARD_FACTOR = 1.25
      ROUND_BRANCH_ENTRY_ARTIFACT_HEIGHT_FACTOR = 1.00
      ROUND_BRANCH_ENTRY_ARTIFACT_SIDE_FACTOR = 0.85

      def self.socket_depth(diameter_or_width, height = nil)
        if height
          [diameter_or_width.to_f, height.to_f].max * SOCKET_DEPTH_FACTOR
        else
          diameter_or_width.to_f * SOCKET_DEPTH_FACTOR
        end
      end

      def self.main_outlet_distance(diameter_or_width, height = nil)
        base = socket_depth(diameter_or_width, height)

        if height
          base + [diameter_or_width.to_f, height.to_f].max * RECTANGULAR_MAIN_EXTRA_FACTOR
        else
          base + diameter_or_width.to_f * ROUND_MAIN_EXTRA_FACTOR
        end
      end

      def self.branch_outlet_distance(diameter_or_width, height = nil)
        base = socket_depth(diameter_or_width, height)

        if height
          base + [diameter_or_width.to_f, height.to_f].max * RECTANGULAR_BRANCH_EXTRA_FACTOR
        else
          base + diameter_or_width.to_f * ROUND_BRANCH_EXTRA_FACTOR
        end
      end

      def self.rectangular_round_branch_outlet_distance(main_width, main_height, branch_diameter, branch_axis, side_axis)
        branch_axis = RectangularFrame.normalized(branch_axis)
        side_axis = RectangularFrame.normalized(side_axis)

        return branch_outlet_distance(branch_diameter) unless branch_axis && side_axis

        side_component = branch_axis.dot(side_axis).abs
        side_component = 0.001 if side_component < 0.001

        sidewall_distance = (main_width.to_f / 2.0) / side_component
        visible_protrusion = branch_diameter.to_f * ROUND_BRANCH_VISIBLE_PROTRUSION_FACTOR

        sidewall_distance + visible_protrusion
      rescue => error
        puts "WyeBuilder.rectangular_round_branch_outlet_distance failed: #{error.message}"
        branch_outlet_distance(branch_diameter)
      end

      def self.branch_pullout_distance(width, height = nil)
        if height
          [width.to_f, height.to_f].max * RECTANGULAR_BRANCH_PULL_OUT_FACTOR
        else
          width.to_f * ROUND_BRANCH_PULL_OUT_FACTOR
        end
      end

      def self.branch_angle
        BRANCH_ANGLE_DEGREES.degrees
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
        branch_shape: nil,
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
            branch_shape: branch_shape,
            branch_diameter: branch_diameter,
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
        puts "WyeBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.branch_vector(forward_vector, side_vector)
        forward_axis = RectangularFrame.normalized(forward_vector)
        side_axis = perpendicularized(side_vector, forward_axis)
        return nil unless forward_axis && side_axis

        c = Math.cos(branch_angle)
        s = Math.sin(branch_angle)

        result = Geom::Vector3d.new(
          forward_axis.x * c + side_axis.x * s,
          forward_axis.y * c + side_axis.y * s,
          forward_axis.z * c + side_axis.z * s
        )

        return nil if result.length == 0

        result.normalize!
        result
      rescue
        nil
      end

    end
  end
end
require_relative 'wye/round_geometry'
require_relative 'wye/rectangular_geometry'
require_relative 'wye/rectangular_visual_geometry'
require_relative 'wye/shared_geometry'
