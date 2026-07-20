module DuctExtension
  module Services
    module GeometryCleanupService
      def self.cleanup_group(group, shape: :round)
        return false unless group && group.valid?

        if shape.to_sym == :rectangular
          keep_rectangular_edges_visible(group)
        else
          soften_round_geometry(group)
        end

        true
      rescue => error
        puts "GeometryCleanupService.cleanup_group failed: #{error.message}"
        false
      end

      def self.soften_round_geometry(group)
        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.soft = true
          edge.smooth = true
          edge.hidden = false
        end
      end

      def self.keep_rectangular_edges_visible(group)
        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.soft = false
          edge.smooth = false
          edge.hidden = false
        end
      end

      private_class_method :soften_round_geometry
      private_class_method :keep_rectangular_edges_visible
    end
  end
end
