module DuctExtension
  module Services
    class FittingRebuildService
      def self.resize(piece:, dimensions:)
        FittingResizeRebuilder.rebuild(
          piece: piece,
          dimensions: dimensions
        )
      end

      def self.swing_rectangular(piece:, connected:, dimensions:, side_axis:)
        RectangularFittingSwingRebuilder.rebuild(
          piece: piece,
          connected: connected,
          dimensions: dimensions,
          side_axis: side_axis
        )
      end
    end
  end
end
