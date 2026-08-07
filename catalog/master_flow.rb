module DuctExtension
  module Catalog
    # Curated pilot subset of the Master Flow ductwork catalog.  The intent is
    # deliberately conservative: only products that map closely to component
    # types already modeled by Simple Duct are included here.
    #
    # `overall` contains published assembled/product envelope dimensions when a
    # reliable manufacturer/retailer specification was available.  Connector
    # dimensions always come from the Master Flow catalog/model number.
    module MasterFlow
      KEY = :master_flow
      NAME = "Master Flow"
      CATALOG_DOCUMENT = "Master Flow Ductwork Product Catalog RESMF164"

      Product = Struct.new(
        :sku,
        :family,
        :name,
        :shape,
        :diameter,
        :width,
        :height,
        :branch_diameter,
        :stock_length,
        :angle_degrees,
        :overall,
        :transition_length,
        :notes,
        keyword_init: true
      ) do
        def label
          text = "#{sku} — #{name}"
          text
        end

        def round?
          shape.to_sym == :round
        rescue
          false
        end

        def rectangular?
          shape.to_sym == :rectangular
        rescue
          false
        end
      end

      module_function

      def product(**kwargs)
        Product.new(**kwargs)
      end

      # Standard 5-ft round metal duct sections.  The drawing tool may cut the
      # stock piece to the requested route length; catalog metadata records both
      # the stock length and modeled cut length.
      ROUND_PIPES = [3, 4, 5, 6, 7, 8, 10, 12, 14].map do |diameter|
        product(
          sku: "CP#{diameter}X60",
          family: :pipe,
          name: "#{diameter}\" Round Metal Duct Pipe, 5 ft section",
          shape: :round,
          diameter: diameter.to_f,
          stock_length: 60.0
        )
      end.freeze

      # Catalog half-section rectangular duct products that most closely match
      # the extension's existing rectangular straight-duct primitive.
      RECTANGULAR_PIPES = [
        ["RD12X8X48", 12.0, 8.0, 48.0],
        ["RD14X8X48", 14.0, 8.0, 48.0],
        ["RD16X8X48", 16.0, 8.0, 48.0],
        ["RD24X8X48", 24.0, 8.0, 48.0],
        ["RD2.25X12X24", 12.0, 2.25, 24.0],
        ["RD3.25X10X36", 10.0, 3.25, 36.0],
        ["RD3.25X12X36", 12.0, 3.25, 36.0],
        ["RD3.25X14X36", 14.0, 3.25, 36.0],
        ["RD3.25X10X60", 10.0, 3.25, 60.0],
        ["RD3.25X12X60", 12.0, 3.25, 60.0],
        ["RD3.25X14X60", 14.0, 3.25, 60.0]
      ].map do |sku, width, height, stock_length|
        product(
          sku: sku,
          family: :pipe,
          name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" Rectangular Duct",
          shape: :rectangular,
          width: width,
          height: height,
          stock_length: stock_length,
          notes: "Master Flow catalogs this as a half-section rectangular duct; modeled geometry represents the assembled rectangular run."
        )
      end.freeze

      # Published product heights are useful for making the procedural elbow
      # occupy approximately the same envelope.  For a quarter-torus model,
      # centerline radius ~= overall height - duct radius.  This is not an attempt
      # to reproduce the segmented swivel seams; it is an envelope constraint.
      ROUND_ELBOWS = [
        ["B90E3",  3.0,  7.0],
        ["B90E4",  4.0,  7.5],
        ["B90E5",  5.0,  9.0],
        ["B90E6",  6.0,  9.0],
        ["90E7",   7.0,  9.0],
        ["90E8",   8.0, 12.0],
        ["90E10", 10.0, 14.0],
        ["90E12", 12.0, 16.0],
        ["90E14", 14.0, 16.0]
      ].map do |sku, diameter, product_height|
        product(
          sku: sku,
          family: :elbow,
          name: "#{diameter.to_s.sub('.0','')}\" 90° Adjustable Round Elbow",
          shape: :round,
          diameter: diameter,
          angle_degrees: 90.0,
          overall: {
            height: product_height,
            width: diameter,
            derived_centerline_radius: [product_height - diameter / 2.0, diameter / 2.0].max
          },
          notes: "Adjustable through 90 degrees; procedural geometry matches the published envelope rather than swivel-seam detail."
        )
      end.freeze

      RECTANGULAR_ELBOWS = [
        product(
          sku: "90E3.25X10",
          family: :elbow,
          name: "10\" x 3-1/4\" Short-Way 90° Rectangular Stack Elbow",
          shape: :rectangular,
          width: 10.0,
          height: 3.25,
          angle_degrees: 90.0,
          overall: { height: 4.5, width: 10.0 },
          notes: "Short-way stack elbow."
        ),
        product(
          sku: "LW90E10X3.25",
          family: :elbow,
          name: "10\" x 3-1/4\" Long-Way 90° Rectangular Stack Elbow",
          shape: :rectangular,
          width: 10.0,
          height: 3.25,
          angle_degrees: 90.0,
          overall: { height: 10.0, width: 10.0 },
          notes: "Long-way stack elbow; catalog says it can be cut to a smaller angle."
        )
      ].freeze

      # Full body dimensions below are published product dimensions.  The 3 in.
      # tee is listed in the catalog, but we intentionally defer it because an
      # independently verifiable assembled H/W/L envelope was not available.
      # That keeps the pilot honest about its “catalog dimensions” promise.
      ROUND_TEES = [
        ["T4X4X4", 4.0, 6.5, 4.0, 8.0],
        ["T5X5X5", 5.0, 10.0, 5.0, 10.0],
        ["T6X6X6", 6.0, 8.5, 6.0, 10.0],
        ["T8X8X8", 8.0, 10.0, 8.0, 12.0]
      ].map do |sku, diameter, h, w, l|
        product(
          sku: sku,
          family: :tee,
          name: "#{diameter.to_s.sub('.0','')}\" Round Tee",
          shape: :round,
          diameter: diameter,
          branch_diameter: diameter,
          angle_degrees: 90.0,
          overall: h ? { height: h, width: w, length: l } : nil,
          notes: "Catalog specifies equal-diameter 90-degree branches; a catalog reducer may follow the branch."
        )
      end.freeze

      # Only equal-size wyes are enabled in the pilot.  Reduced Y8X6X6 and
      # Y10X8X8 exist in the catalog, but the extension intentionally keeps a
      # stable native branch socket plus a separate transition.  Using the equal
      # wye + catalog reducer preserves that proven topology without pretending
      # an integral reducing wye has the same geometry.
      ROUND_WYES = [
        ["Y4X4X4", 4.0, 8.5, 11.0, 4.0],
        ["Y6X6X6", 6.0, 11.75, 13.0, 6.0],
        ["Y8X8X8", 8.0, 16.0, 16.0, 8.0]
      ].map do |sku, diameter, h, w, l|
        product(
          sku: sku,
          family: :wye,
          name: "#{diameter.to_s.sub('.0','')}\" Equal Round Wye",
          shape: :round,
          diameter: diameter,
          branch_diameter: diameter,
          angle_degrees: 45.0,
          overall: { height: h, width: w, length: l },
          notes: "Equal-size catalog wye; branch reducers are separate catalog pieces when needed."
        )
      end.freeze

      # Axial lengths are published assembled/product heights where available.
      # R8X6 uses the manufacturer's explicit Q&A overall length (8-3/8 in),
      # which is more specific than the generic retailer dimension table.
      ROUND_REDUCERS = [
        ["R4X3",   4.0,  3.0, 6.375],
        ["R5X4",   5.0,  4.0, 5.5],
        ["R6X4",   6.0,  4.0, 6.0],
        ["R6X5",   6.0,  5.0, 5.5],
        ["R7X4",   7.0,  4.0, 6.0],
        ["R7X6",   7.0,  6.0, 5.875],
        ["R8X6",   8.0,  6.0, 8.375],
        ["R8X7",   8.0,  7.0, 6.0],
        ["R10X8", 10.0,  8.0, 6.0],
        ["R12X10",12.0, 10.0, 8.0],
        ["R14X12",14.0, 12.0, 8.0]
      ].map do |sku, large, small, length|
        product(
          sku: sku,
          family: :transition,
          name: "#{large.to_s.sub('.0','')}\" to #{small.to_s.sub('.0','')}\" Round Reducer / Increaser",
          shape: :round,
          diameter: large,
          branch_diameter: small,
          transition_length: length,
          overall: { diameter: large, length: length }
        )
      end.freeze

      STACK_BOOTS = [
        ["SB10X3.25X4", 10.0, 3.25, 4.0, { height: 10.0, width: 6.0, depth: 4.0 }, 10.0],
        ["SB10X3.25X5", 10.0, 3.25, 5.0, { retailer_height: 10.0, retailer_width: 6.0, retailer_depth: 5.0, manufacturer_stated_height: 7.0 }, 7.0],
        ["SB10X3.25X6", 10.0, 3.25, 6.0, { height: 6.0, width: 10.0, depth: 6.0 }, 6.0],
        ["SB10X3.25X7", 10.0, 3.25, 7.0, { height: 6.0, width: 10.0, depth: 7.0 }, 6.0],
        ["SB12X2.25X6", 12.0, 2.25, 6.0, { height: 10.0, width: 12.0, depth: 8.0 }, 10.0]
      ].map do |sku, width, height, diameter, overall, length|
        product(
          sku: sku,
          family: :transition,
          name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" to #{diameter.to_s.sub('.0','')}\" Stack Boot",
          shape: :mixed,
          width: width,
          height: height,
          diameter: diameter,
          transition_length: length,
          overall: overall,
          notes: "Straight-line round-to-rectangular stack boot."
        )
      end.freeze

      END_COVERS = [
        product(
          sku: "DC3.25X10",
          family: :end_cover,
          name: "10\" x 3-1/4\" Rectangular Stack Duct Cap",
          shape: :rectangular,
          width: 10.0,
          height: 3.25
        )
      ].freeze

      # Product rows that are useful reference but intentionally not enabled as
      # first-pass geometry because they do not map cleanly to the extension's
      # current topology/primitive semantics.
      DEFERRED_PRODUCTS = [
        product(sku: "T3X3X3", family: :tee, name: "3\" Round Tee (nominal size verified; body envelope deferred)", shape: :round, diameter: 3.0, branch_diameter: 3.0),
        product(sku: "Y8X6X6", family: :wye, name: "8\" to 6\" x 6\" Integral Reducing Wye", shape: :round, diameter: 8.0, branch_diameter: 6.0, overall: { height: 12.5, width: 15.0, length: 8.0 }),
        product(sku: "Y10X8X8", family: :wye, name: "10\" to 8\" x 8\" Integral Reducing Wye", shape: :round, diameter: 10.0, branch_diameter: 8.0, overall: { height: 16.0, width: 16.0, length: 10.0 })
      ].freeze

      PRODUCTS = (
        ROUND_PIPES + RECTANGULAR_PIPES +
        ROUND_ELBOWS + RECTANGULAR_ELBOWS +
        ROUND_TEES + ROUND_WYES + ROUND_REDUCERS + STACK_BOOTS + END_COVERS
      ).freeze

      def products
        PRODUCTS
      end
    end
  end
end
