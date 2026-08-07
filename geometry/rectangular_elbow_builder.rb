module DuctExtension
  module Geometry
    module RectangularElbowBuilder
      SEGMENTS = 16
      EPSILON = 0.000001

      # A normal 90-degree route elbow may absorb at most 15 degrees of roll.
      # Smaller bends absorb proportionally less. This lets several elbows bring
      # an awkward rectangular frame back toward level without twisting straight
      # duct or forcing one elbow to perform an unrealistic full rotation.
      RELEVEL_MAX_ROLL_PER_RIGHT_ANGLE = 15.0 * Math::PI / 180.0
      RELEVEL_MIN_ROLL = 2.0 * Math::PI / 180.0
      RELEVEL_REFERENCE_RADIUS_FACTOR = 1.50
      RELEVEL_MIN_RADIUS_SCALE = 0.25
      RELEVEL_GORE_COUNT = 4
      EDGE_KEY_PRECISION = 6

      def self.build_into(
        group,
        start_point,
        entry_vector,
        exit_vector,
        width,
        height,
        bend_radius,
        cap_start: false,
        cap_end: false,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        allow_relevel: false,
        frame_plan: nil
      )
        return false unless group && group.valid?

        start_point = RectangularFrame.point3d(start_point)
        entry_vector = RectangularFrame.normalized(entry_vector)
        exit_vector = RectangularFrame.normalized(exit_vector)

        width = width.to_f
        height = height.to_f
        bend_radius = bend_radius.to_f

        return false unless start_point && entry_vector && exit_vector
        return false if width <= 0.0 || height <= 0.0 || bend_radius <= 0.0

        frame_plan ||= self.frame_plan(
          start_point: start_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          bend_radius: bend_radius,
          width: width,
          height: height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          allow_relevel: allow_relevel
        )
        return false unless frame_plan

        arc = frame_plan[:arc]
        start_basis = frame_plan[:start_basis]
        correction_roll = frame_plan[:roll_angle].to_f

        sections = []
        origin = Geom::Point3d.new(0, 0, 0)

        (SEGMENTS + 1).times do |index|
          t = index.to_f / SEGMENTS.to_f
          theta = arc[:angle] * t

          bend_transform = Geom::Transformation.rotation(
            arc[:center],
            arc[:normal],
            theta
          )

          section_center = start_point.transform(bend_transform)
          section_axis = entry_vector.transform(bend_transform)
          section_width_axis = start_basis[:width_axis].transform(bend_transform)
          section_height_axis = start_basis[:height_axis].transform(bend_transform)

          section_axis.normalize!
          section_width_axis.normalize!
          section_height_axis.normalize!

          # Keep the socket ends exact while easing the permitted roll through the
          # body of the elbow. smoothstep gives zero roll rate at both ends, which
          # avoids a visible kink where straight duct meets the fitting.
          roll_at_section = correction_roll * smoothstep(t)

          if roll_at_section.abs > EPSILON
            roll_transform = Geom::Transformation.rotation(
              origin,
              section_axis,
              roll_at_section
            )

            section_width_axis = section_width_axis.transform(roll_transform)
            section_height_axis = section_height_axis.transform(roll_transform)
          end

          section_basis = RectangularFrame.basis_for_axis(
            section_axis,
            preferred_width_axis: section_width_axis,
            preferred_height_axis: section_height_axis
          )
          return false unless section_basis

          corners = RectangularFrame.rectangle_corners_from_basis(
            section_center,
            section_basis[:width_axis],
            section_basis[:height_axis],
            width,
            height
          )
          return false if corners.empty?

          sections << {
            center: section_center,
            axis: section_axis,
            width_axis: section_basis[:width_axis],
            height_axis: section_basis[:height_axis],
            corners: corners
          }
        end

        entities = group.entities

        SEGMENTS.times do |section_index|
          current = sections[section_index][:corners]
          nxt = sections[section_index + 1][:corners]

          4.times do |corner_index|
            next_corner_index = (corner_index + 1) % 4

            Mesh.add_quad(
              entities,
              current[corner_index],
              current[next_corner_index],
              nxt[next_corner_index],
              nxt[corner_index]
            )
          end
        end

        if cap_start
          Mesh.add_face_safe(
            entities,
            sections.first[:corners].reverse,
            reverse_if_normal_against: entry_vector.clone.reverse
          )
        end

        if cap_end
          Mesh.add_face_safe(
            entities,
            sections.last[:corners],
            reverse_if_normal_against: exit_vector
          )
        end

        if frame_plan[:relevel]
          style_rolled_elbow_edges(group, sections)
        else
          Mesh.keep_edges_visible(group)
        end

        Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "RectangularElbowBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.exit_point(start_point, entry_vector, exit_vector, bend_radius)
        ElbowBuilder.exit_point(start_point, entry_vector, exit_vector, bend_radius)
      end

      # Shared geometry/metadata plan. GeometryExecutor passes this exact plan to
      # build_into and also uses its end_basis for the elbow's output port, so the
      # visible socket and semantic port frame cannot drift apart.
      def self.frame_plan(
        start_point:,
        entry_vector:,
        exit_vector:,
        bend_radius:,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        width: nil,
        height: nil,
        allow_relevel: false
      )
        start_point = RectangularFrame.point3d(start_point)
        entry_vector = RectangularFrame.normalized(entry_vector)
        exit_vector = RectangularFrame.normalized(exit_vector)

        width = width.to_f
        height = height.to_f
        bend_radius = bend_radius.to_f

        return nil unless start_point && entry_vector && exit_vector
        return nil if width <= 0.0 || height <= 0.0 || bend_radius <= 0.0

        arc = ElbowBuilder.send(
          :arc_data,
          start_point: start_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          bend_radius: bend_radius
        )
        return nil unless arc

        # The entry socket always inherits the exact incoming frame.
        start_basis = RectangularFrame.stable_basis_for_axis(
          entry_vector,
          width,
          height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          allow_relevel: false
        )
        return nil unless start_basis

        bend_transform = Geom::Transformation.rotation(
          arc[:center],
          arc[:normal],
          arc[:angle]
        )

        transported_width = start_basis[:width_axis].transform(bend_transform)
        transported_height = start_basis[:height_axis].transform(bend_transform)

        transported_end_basis = RectangularFrame.basis_for_axis(
          exit_vector,
          preferred_width_axis: transported_width,
          preferred_height_axis: transported_height
        )
        return nil unless transported_end_basis

        unchanged = {
          arc: arc,
          start_basis: start_basis,
          transported_end_basis: transported_end_basis,
          end_basis: transported_end_basis,
          roll_angle: 0.0,
          remaining_roll_angle: 0.0,
          relevel: false
        }

        return unchanged unless allow_relevel

        max_roll = relevel_capacity(
          bend_angle: arc[:angle],
          bend_radius: bend_radius,
          largest_dimension: [width, height].max
        )
        return unchanged if max_roll <= EPSILON

        relevel_plan = RectangularFrame.limited_relevel_plan(
          axis: exit_vector,
          basis: transported_end_basis,
          width: width,
          height: height,
          max_roll: max_roll,
          minimum_roll: RELEVEL_MIN_ROLL
        )
        return unchanged unless relevel_plan

        unchanged.merge(
          end_basis: relevel_plan[:end_basis],
          roll_angle: relevel_plan[:roll_angle],
          remaining_roll_angle: relevel_plan[:remaining_roll_angle],
          relevel: relevel_plan[:relevel]
        )
      rescue => error
        puts "RectangularElbowBuilder.frame_plan failed: #{error.message}"
        nil
      end

      def self.exit_basis(
        start_point:,
        entry_vector:,
        exit_vector:,
        bend_radius:,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        width: nil,
        height: nil,
        allow_relevel: false
      )
        plan = frame_plan(
          start_point: start_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          bend_radius: bend_radius,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          width: width,
          height: height,
          allow_relevel: allow_relevel
        )

        plan && plan[:end_basis]
      rescue => error
        puts "RectangularElbowBuilder.exit_basis failed: #{error.message}"
        nil
      end

      def self.relevel_capacity(bend_angle:, bend_radius:, largest_dimension:)
        bend_fraction = bend_angle.to_f.abs / (Math::PI / 2.0)
        bend_fraction = [[bend_fraction, 0.0].max, 1.0].min

        largest_dimension = largest_dimension.to_f
        return 0.0 if largest_dimension <= EPSILON

        reference_radius = largest_dimension * RELEVEL_REFERENCE_RADIUS_FACTOR
        radius_scale = bend_radius.to_f / reference_radius
        radius_scale = [[radius_scale, RELEVEL_MIN_RADIUS_SCALE].max, 1.0].min

        RELEVEL_MAX_ROLL_PER_RIGHT_ANGLE * bend_fraction * radius_scale
      rescue
        0.0
      end
      private_class_method :relevel_capacity

      def self.smoothstep(value)
        t = [[value.to_f, 0.0].max, 1.0].min
        t * t * (3.0 - 2.0 * t)
      end
      private_class_method :smoothstep

      def self.style_rolled_elbow_edges(group, sections)
        visible = {}

        # Keep true socket rings.
        [sections.first, sections.last].each do |section|
          4.times do |index|
            visible[segment_key(section[:corners][index], section[:corners][(index + 1) % 4])] = true
          end
        end

        # Keep the four corner seams along the elbow body.
        (sections.length - 1).times do |section_index|
          4.times do |corner_index|
            visible[
              segment_key(
                sections[section_index][:corners][corner_index],
                sections[section_index + 1][:corners][corner_index]
              )
            ] = true
          end
        end

        # Show only a few transverse gore lines rather than all tessellation rings.
        gore_stride = [(SEGMENTS.to_f / RELEVEL_GORE_COUNT).round, 1].max
        gore_stride.step(SEGMENTS - 1, gore_stride) do |section_index|
          corners = sections[section_index][:corners]
          4.times do |corner_index|
            visible[segment_key(corners[corner_index], corners[(corner_index + 1) % 4])] = true
          end
        end

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          if visible[segment_key(edge.start.position, edge.end.position)]
            edge.hidden = false
            edge.soft = false if edge.respond_to?(:soft=)
            edge.smooth = false if edge.respond_to?(:smooth=)
          else
            edge.hidden = true
            edge.soft = true if edge.respond_to?(:soft=)
            edge.smooth = true if edge.respond_to?(:smooth=)
          end
        end
      rescue => error
        puts "RectangularElbowBuilder.style_rolled_elbow_edges failed: #{error.message}"
        Mesh.keep_edges_visible(group)
      end
      private_class_method :style_rolled_elbow_edges

      def self.segment_key(point_a, point_b)
        a = point_key(point_a)
        b = point_key(point_b)
        a <= b ? [a, b] : [b, a]
      end
      private_class_method :segment_key

      def self.point_key(point)
        [
          point.x.to_f.round(EDGE_KEY_PRECISION),
          point.y.to_f.round(EDGE_KEY_PRECISION),
          point.z.to_f.round(EDGE_KEY_PRECISION)
        ]
      end
      private_class_method :point_key
    end
  end
end
