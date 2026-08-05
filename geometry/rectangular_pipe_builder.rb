module DuctExtension
  module Geometry
    module RectangularPipeBuilder
      OVERLAP_FACTOR = 0.0
      EPSILON = 0.000001
      EDGE_KEY_PRECISION = 6

      def self.build_into(
        group,
        start_point,
        end_point,
        width,
        height,
        overlap_start: false,
        overlap_end: false,
        cap_start: true,
        cap_end: true,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        allow_relevel: true,
        frame_plan: nil
      )
        return false unless group && group.valid?

        start_point = RectangularFrame.point3d(start_point)
        end_point = RectangularFrame.point3d(end_point)

        width = width.to_f
        height = height.to_f

        return false unless start_point && end_point
        return false if width <= 0.0 || height <= 0.0

        direction = start_point.vector_to(end_point)
        total_length = direction.length
        return false if total_length <= EPSILON

        direction.normalize!

        largest = [width, height].max
        overlap = largest * OVERLAP_FACTOR

        mesh_start = overlap_start ? start_point.offset(direction.clone.reverse, overlap) : start_point
        mesh_end = overlap_end ? end_point.offset(direction, overlap) : end_point
        mesh_length = mesh_start.distance(mesh_end)

        # Automatic rolling is opt-in through an explicit frame_plan. Existing
        # fitting/rebuild callers keep their historical single-frame behavior,
        # while GeometryExecutor may supply a safe start-to-end relevel plan.
        frame_plan ||= RectangularFrame.straight_run_plan(
          axis: direction,
          length: mesh_length,
          width: width,
          height: height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          allow_relevel: false
        )

        return false unless frame_plan

        if frame_plan[:relevel] && frame_plan[:segments].to_i > 1
          build_releveling_run(
            group: group,
            mesh_start: mesh_start,
            mesh_end: mesh_end,
            direction: direction,
            width: width,
            height: height,
            frame_plan: frame_plan,
            cap_start: cap_start,
            cap_end: cap_end
          )
        else
          build_straight_run(
            group: group,
            mesh_start: mesh_start,
            mesh_end: mesh_end,
            direction: direction,
            width: width,
            height: height,
            basis: frame_plan[:start_basis],
            cap_start: cap_start,
            cap_end: cap_end
          )
        end
      rescue => error
        puts "RectangularPipeBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_straight_run(
        group:,
        mesh_start:,
        mesh_end:,
        direction:,
        width:,
        height:,
        basis:,
        cap_start:,
        cap_end:
      )
        return false unless basis

        start_corners = RectangularFrame.rectangle_corners_from_basis(
          mesh_start,
          basis[:width_axis],
          basis[:height_axis],
          width,
          height
        )

        end_corners = RectangularFrame.rectangle_corners_from_basis(
          mesh_end,
          basis[:width_axis],
          basis[:height_axis],
          width,
          height
        )

        return false if start_corners.empty? || end_corners.empty?

        entities = group.entities
        add_section_strip(entities, start_corners, end_corners)
        add_caps(
          entities: entities,
          start_corners: start_corners,
          end_corners: end_corners,
          direction: direction,
          cap_start: cap_start,
          cap_end: cap_end
        )

        Mesh.keep_edges_visible(group)
        Mesh.apply_material_from_group(group)
        true
      end
      private_class_method :build_straight_run

      def self.build_releveling_run(
        group:,
        mesh_start:,
        mesh_end:,
        direction:,
        width:,
        height:,
        frame_plan:,
        cap_start:,
        cap_end:
      )
        segments = frame_plan[:segments].to_i
        return false if segments < 2

        total_length = mesh_start.distance(mesh_end)
        roll_angle = frame_plan[:roll_angle].to_f
        start_basis = frame_plan[:start_basis]
        return false unless start_basis

        sections = []
        origin = Geom::Point3d.new(0, 0, 0)

        (segments + 1).times do |index|
          fraction = index.to_f / segments.to_f
          center = mesh_start.offset(direction, total_length * fraction)

          rotation = Geom::Transformation.rotation(
            origin,
            direction,
            roll_angle * fraction
          )

          width_axis = start_basis[:width_axis].transform(rotation)
          height_axis = start_basis[:height_axis].transform(rotation)

          basis = RectangularFrame.basis_for_axis(
            direction,
            preferred_width_axis: width_axis,
            preferred_height_axis: height_axis
          )
          return false unless basis

          corners = RectangularFrame.rectangle_corners_from_basis(
            center,
            basis[:width_axis],
            basis[:height_axis],
            width,
            height
          )
          return false if corners.empty?

          sections << corners
        end

        entities = group.entities
        segments.times do |index|
          add_section_strip(entities, sections[index], sections[index + 1])
        end

        add_caps(
          entities: entities,
          start_corners: sections.first,
          end_corners: sections.last,
          direction: direction,
          cap_start: cap_start,
          cap_end: cap_end
        )

        style_releveling_edges(group, sections)
        Mesh.apply_material_from_group(group)
        true
      end
      private_class_method :build_releveling_run

      def self.add_section_strip(entities, section_a, section_b)
        4.times do |index|
          next_index = (index + 1) % 4
          Mesh.add_quad(
            entities,
            section_a[index],
            section_a[next_index],
            section_b[next_index],
            section_b[index]
          )
        end
      end
      private_class_method :add_section_strip

      def self.add_caps(
        entities:,
        start_corners:,
        end_corners:,
        direction:,
        cap_start:,
        cap_end:
      )
        if cap_start
          Mesh.add_face_safe(
            entities,
            start_corners.reverse,
            reverse_if_normal_against: direction.clone.reverse
          )
        end

        if cap_end
          Mesh.add_face_safe(
            entities,
            end_corners,
            reverse_if_normal_against: direction
          )
        end
      end
      private_class_method :add_caps

      def self.style_releveling_edges(group, sections)
        visible = {}

        [sections.first, sections.last].each do |section|
          4.times do |index|
            next_index = (index + 1) % 4
            visible[segment_key(section[index], section[next_index])] = true
          end
        end

        (sections.length - 1).times do |section_index|
          4.times do |corner_index|
            visible[
              segment_key(
                sections[section_index][corner_index],
                sections[section_index + 1][corner_index]
              )
            ] = true
          end
        end

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          key = segment_key(edge.start.position, edge.end.position)
          if visible[key]
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
        puts "RectangularPipeBuilder.style_releveling_edges failed: #{error.message}"
      end
      private_class_method :style_releveling_edges

      def self.segment_key(point_a, point_b)
        [point_key(point_a), point_key(point_b)].sort.join("|")
      end
      private_class_method :segment_key

      def self.point_key(point)
        [point.x, point.y, point.z].map do |value|
          value.to_f.round(EDGE_KEY_PRECISION)
        end.join(",")
      end
      private_class_method :point_key
    end
  end
end
