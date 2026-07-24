module DuctExtension
  module Services
    class FittingResizeRebuilder
      extend FittingRebuildSupport

      EPSILON = FittingRebuildSupport::EPSILON

      def self.rebuild(piece:, dimensions:)
        return false unless piece
        return false unless piece.group && piece.group.valid?

        case piece.type.to_sym
        when :tee
          rebuild_tee_fitting!(piece, dimensions)
        when :wye
          rebuild_wye_fitting!(piece, dimensions)
        when :cross
          rebuild_cross_fitting!(piece, dimensions)
        else
          false
        end
      rescue => error
        puts "FittingResizeRebuilder.rebuild failed for #{piece&.type}: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_tee_fitting!(piece, dimensions)
        rebuild_three_way_fitting!(piece, dimensions, fitting_type: :tee)
      end

      def self.rebuild_three_way_fitting!(piece, dimensions, fitting_type:)
        ports = Array(piece.ports).compact
        return false unless ports.length >= 3

        main_a, main_b, branch_port = tee_port_layout(ports)
        return false unless main_a && main_b && branch_port

        center = midpoint(main_a.point, main_b.point)
        return false unless center

        main_axis = main_a.point.vector_to(main_b.point)
        return false if main_axis.length <= EPSILON
        main_axis.normalize!

        branch_axis = center.vector_to(branch_port.point)
        if branch_axis.length <= EPSILON && branch_port.outward_vector
          branch_axis = branch_port.outward_vector.clone
        end
        return false if branch_axis.length <= EPSILON
        branch_axis.normalize!

        erase_group_geometry(piece.group)

        shared_args = {
          group: piece.group,
          center: center,
          main_a: main_a,
          main_b: main_b,
          branch_port: branch_port,
          main_axis: main_axis,
          branch_axis: branch_axis,
          dimensions: dimensions
        }

        success =
          if dimensions[:shape] == :rectangular
            rebuild_rectangular_three_way_geometry(
              **shared_args,
              wye_style: fitting_type == :wye
            )
          else
            rebuild_round_three_way_geometry(**shared_args)
          end

        return false unless success

        update_fitting_port_dimensions!(
          ports: ports,
          center: center,
          dimensions: dimensions
        )

        true
      rescue => error
        puts "FittingResizeRebuilder.rebuild_three_way_fitting! failed for #{fitting_type}: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_cross_fitting!(piece, dimensions)
        ports = Array(piece.ports).compact
        return false unless ports.length >= 4

        pair_a, pair_b = cross_port_layout(ports)
        return false unless pair_a && pair_b
        return false unless pair_a.length == 2 && pair_b.length == 2

        center = average_point(ports.map(&:point))
        return false unless center

        axis_a = pair_a[0].point.vector_to(pair_a[1].point)
        axis_b = pair_b[0].point.vector_to(pair_b[1].point)

        return false if axis_a.length <= EPSILON
        return false if axis_b.length <= EPSILON

        axis_a.normalize!
        axis_b.normalize!

        erase_group_geometry(piece.group)

        success =
          if dimensions[:shape] == :rectangular
            rebuild_rectangular_cross_geometry(
              group: piece.group,
              center: center,
              pair_a: pair_a,
              pair_b: pair_b,
              axis_a: axis_a,
              axis_b: axis_b,
              dimensions: dimensions
            )
          else
            rebuild_round_cross_geometry(
              group: piece.group,
              center: center,
              pair_a: pair_a,
              pair_b: pair_b,
              axis_a: axis_a,
              axis_b: axis_b,
              dimensions: dimensions
            )
          end

        return false unless success

        update_fitting_port_dimensions!(
          ports: ports,
          center: center,
          dimensions: dimensions
        )

        true
      rescue => error
        puts "FittingResizeRebuilder.rebuild_cross_fitting! failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_wye_fitting!(piece, dimensions)
        rebuild_three_way_fitting!(piece, dimensions, fitting_type: :wye)
      end

      def self.rebuild_round_three_way_geometry(group:, center:, main_a:, main_b:, branch_port:, main_axis:, branch_axis:, dimensions:)
        Geometry::PipeBuilder.build_into(
          group,
          main_a.point,
          main_b.point,
          dimensions[:diameter],
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        Geometry::PipeBuilder.build_into(
          group,
          center,
          branch_port.point,
          dimensions[:diameter],
          overlap_start: true,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        add_round_tee_like_hub(
          group: group,
          center: center,
          main_axis: main_axis,
          branch_axis: branch_axis,
          diameter: dimensions[:diameter]
        )

        Geometry::Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "FittingResizeRebuilder.rebuild_round_three_way_geometry failed: #{error.message}"
        false
      end

      def self.rebuild_round_cross_geometry(group:, center:, pair_a:, pair_b:, axis_a:, axis_b:, dimensions:)
        Geometry::PipeBuilder.build_into(
          group,
          pair_a[0].point,
          pair_a[1].point,
          dimensions[:diameter],
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        Geometry::PipeBuilder.build_into(
          group,
          pair_b[0].point,
          pair_b[1].point,
          dimensions[:diameter],
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        add_round_cross_like_hub(
          group: group,
          center: center,
          axis_a: axis_a,
          axis_b: axis_b,
          diameter: dimensions[:diameter]
        )

        Geometry::Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "FittingResizeRebuilder.rebuild_round_cross_geometry failed: #{error.message}"
        false
      end

      def self.rebuild_rectangular_three_way_geometry(group:, center:, main_a:, main_b:, branch_port:, main_axis:, branch_axis:, dimensions:, wye_style:)
        main_basis = fitting_rectangular_basis_for_axis(main_axis, dimensions, main_a, main_b)
        branch_basis = fitting_rectangular_basis_for_axis(branch_axis, dimensions, branch_port, main_a)
        return false unless main_basis && branch_basis

        Geometry::RectangularPipeBuilder.build_into(
          group,
          main_a.point,
          main_b.point,
          dimensions[:width],
          dimensions[:height],
          width_axis: main_basis[:width_axis],
          height_axis: main_basis[:height_axis],
          cap_start: false,
          cap_end: false
        )

        Geometry::RectangularPipeBuilder.build_into(
          group,
          center,
          branch_port.point,
          dimensions[:width],
          dimensions[:height],
          width_axis: branch_basis[:width_axis],
          height_axis: branch_basis[:height_axis],
          cap_start: false,
          cap_end: false
        )

        add_rectangular_center_box(
          group: group,
          center: center,
          axis_a: main_axis,
          axis_b: branch_axis,
          dimensions: dimensions,
          basis_a: main_basis,
          basis_b: branch_basis,
          wye_style: wye_style
        )

        Geometry::Mesh.keep_edges_visible(group)
        Geometry::Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "FittingResizeRebuilder.rebuild_rectangular_three_way_geometry failed: #{error.message}"
        false
      end

      def self.rebuild_rectangular_cross_geometry(group:, center:, pair_a:, pair_b:, axis_a:, axis_b:, dimensions:)
        basis_a = fitting_rectangular_basis_for_axis(axis_a, dimensions, pair_a[0], pair_a[1])
        basis_b = fitting_rectangular_basis_for_axis(axis_b, dimensions, pair_b[0], pair_b[1])
        return false unless basis_a && basis_b

        Geometry::RectangularPipeBuilder.build_into(
          group,
          pair_a[0].point,
          pair_a[1].point,
          dimensions[:width],
          dimensions[:height],
          width_axis: basis_a[:width_axis],
          height_axis: basis_a[:height_axis],
          cap_start: false,
          cap_end: false
        )

        Geometry::RectangularPipeBuilder.build_into(
          group,
          pair_b[0].point,
          pair_b[1].point,
          dimensions[:width],
          dimensions[:height],
          width_axis: basis_b[:width_axis],
          height_axis: basis_b[:height_axis],
          cap_start: false,
          cap_end: false
        )

        add_rectangular_center_box(
          group: group,
          center: center,
          axis_a: axis_a,
          axis_b: axis_b,
          dimensions: dimensions,
          basis_a: basis_a,
          basis_b: basis_b,
          wye_style: false
        )

        Geometry::Mesh.keep_edges_visible(group)
        Geometry::Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "FittingResizeRebuilder.rebuild_rectangular_cross_geometry failed: #{error.message}"
        false
      end

      def self.add_round_tee_like_hub(group:, center:, main_axis:, branch_axis:, diameter:)
        if Geometry::TeeBuilder.respond_to?(:add_hub_cover, true)
          Geometry::TeeBuilder.send(
            :add_hub_cover,
            group: group,
            center: center,
            forward_vector: main_axis,
            side_vector: branch_axis,
            diameter: diameter
          )
        else
          add_round_ball_hub(
            group: group,
            center: center,
            diameter: diameter
          )
        end
      rescue
        add_round_ball_hub(
          group: group,
          center: center,
          diameter: diameter
        )
      end

      def self.add_round_cross_like_hub(group:, center:, axis_a:, axis_b:, diameter:)
        if Geometry::CrossBuilder.respond_to?(:add_oval_hub, true)
          Geometry::CrossBuilder.send(
            :add_oval_hub,
            group: group,
            center: center,
            forward_vector: axis_a,
            side_vector: axis_b,
            diameter: diameter
          )
        else
          add_round_ball_hub(
            group: group,
            center: center,
            diameter: diameter
          )
        end
      rescue
        add_round_ball_hub(
          group: group,
          center: center,
          diameter: diameter
        )
      end

      def self.add_round_ball_hub(group:, center:, diameter:)
        radius = diameter.to_f * 0.58
        segments = 16
        rings = 8

        entities = group.entities
        z_axis = Geom::Vector3d.new(0, 0, 1)
        x_axis = Geom::Vector3d.new(1, 0, 0)
        y_axis = Geom::Vector3d.new(0, 1, 0)

        rings_points = []

        (rings + 1).times do |ring_index|
          phi = -Math::PI / 2.0 + Math::PI * ring_index.to_f / rings.to_f
          z = Math.sin(phi) * radius
          ring_radius = Math.cos(phi) * radius
          ring = []

          segments.times do |segment_index|
            theta = Math::PI * 2.0 * segment_index.to_f / segments.to_f

            point = Geom::Point3d.new(
              center.x + x_axis.x * Math.cos(theta) * ring_radius + y_axis.x * Math.sin(theta) * ring_radius + z_axis.x * z,
              center.y + x_axis.y * Math.cos(theta) * ring_radius + y_axis.y * Math.sin(theta) * ring_radius + z_axis.y * z,
              center.z + x_axis.z * Math.cos(theta) * ring_radius + y_axis.z * Math.sin(theta) * ring_radius + z_axis.z * z
            )

            ring << point
          end

          rings_points << ring
        end

        rings.times do |ring_index|
          current = rings_points[ring_index]
          nxt = rings_points[ring_index + 1]

          segments.times do |segment_index|
            next_index = (segment_index + 1) % segments
            Geometry::Mesh.add_quad(
              entities,
              current[segment_index],
              current[next_index],
              nxt[next_index],
              nxt[segment_index]
            )
          end
        end

        Geometry::Mesh.soft_smooth_round_edges(group) if Geometry::Mesh.respond_to?(:soft_smooth_round_edges)
      rescue => error
        puts "FittingResizeRebuilder.add_round_ball_hub failed: #{error.message}"
      end

      def self.add_rectangular_center_box(group:, center:, axis_a:, axis_b:, dimensions:, basis_a:, basis_b:, wye_style:)
        axis_a = Geometry::RectangularFrame.normalized(axis_a)
        axis_b = Geometry::RectangularFrame.normalized(axis_b)
        return false unless axis_a && axis_b

        normal_axis = axis_a.cross(axis_b)
        if normal_axis.length <= EPSILON
          normal_axis = basis_a[:height_axis] || basis_b[:height_axis]
        end
        return false unless normal_axis && normal_axis.length > EPSILON
        normal_axis.normalize!

        side_axis = normal_axis.cross(axis_a)
        return false if side_axis.length <= EPSILON
        side_axis.normalize!

        largest = [dimensions[:width].to_f, dimensions[:height].to_f].max

        half_a = largest * (wye_style ? 0.52 : 0.58)
        half_b = largest * (wye_style ? 0.46 : 0.58)
        half_h = dimensions[:height].to_f / 2.0

        entities = group.entities

        p000 = box_point(center, axis_a, side_axis, normal_axis, -half_a, -half_b, -half_h)
        p001 = box_point(center, axis_a, side_axis, normal_axis, -half_a, -half_b,  half_h)
        p010 = box_point(center, axis_a, side_axis, normal_axis, -half_a,  half_b, -half_h)
        p011 = box_point(center, axis_a, side_axis, normal_axis, -half_a,  half_b,  half_h)

        p100 = box_point(center, axis_a, side_axis, normal_axis,  half_a, -half_b, -half_h)
        p101 = box_point(center, axis_a, side_axis, normal_axis,  half_a, -half_b,  half_h)
        p110 = box_point(center, axis_a, side_axis, normal_axis,  half_a,  half_b, -half_h)
        p111 = box_point(center, axis_a, side_axis, normal_axis,  half_a,  half_b,  half_h)

        Geometry::Mesh.add_quad(entities, p000, p001, p011, p010)
        Geometry::Mesh.add_quad(entities, p100, p110, p111, p101)
        Geometry::Mesh.add_quad(entities, p000, p100, p101, p001)
        Geometry::Mesh.add_quad(entities, p010, p011, p111, p110)
        Geometry::Mesh.add_quad(entities, p000, p010, p110, p100)
        Geometry::Mesh.add_quad(entities, p001, p101, p111, p011)

        add_visible_edge(entities, p000, p001)
        add_visible_edge(entities, p001, p011)
        add_visible_edge(entities, p011, p010)
        add_visible_edge(entities, p010, p000)

        add_visible_edge(entities, p100, p101)
        add_visible_edge(entities, p101, p111)
        add_visible_edge(entities, p111, p110)
        add_visible_edge(entities, p110, p100)

        add_visible_edge(entities, p000, p100)
        add_visible_edge(entities, p001, p101)
        add_visible_edge(entities, p010, p110)
        add_visible_edge(entities, p011, p111)

        true
      rescue => error
        puts "FittingResizeRebuilder.add_rectangular_center_box failed: #{error.message}"
        false
      end

    end
  end
end
