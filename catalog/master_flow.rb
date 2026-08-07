module DuctExtension
  module Catalog
    # Master Flow catalog data for the product families currently modeled by
    # Simple Duct. Connector sizes/SKUs come directly from RESMF164. Geometry
    # fields describe the stocked product so catalog mode can build a rigid,
    # recognizable fitting rather than merely tagging generic geometry.
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
        :outlet_diameter,
        :stock_length,
        :angle_degrees,
        :overall,
        :transition_length,
        :style,
        :notes,
        keyword_init: true
      ) do
        def label
          "#{sku} — #{name}"
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

        def mixed?
          shape.to_sym == :mixed
        rescue
          false
        end
      end

      module_function

      def product(**kwargs)
        Product.new(**kwargs)
      end

      # ---- STRAIGHT ROUND DUCT -------------------------------------------------
      # RESMF164 lists 2-ft and 3-ft snap-lock pipe, 5-ft beaded pipe, and
      # standard 5-ft round metal duct. All listed sizes are represented.
      ROUND_PIPES = begin
        products = []

        [3, 4, 5, 6, 7, 8].each do |diameter|
          products << product(
            sku: "BCP#{diameter}X24",
            family: :pipe,
            name: "#{diameter}\" Round Metal Duct Pipe, 2 ft section",
            shape: :round,
            diameter: diameter.to_f,
            stock_length: 24.0,
            style: :snap_lock
          )
          products << product(
            sku: "BCP#{diameter}X36",
            family: :pipe,
            name: "#{diameter}\" Round Metal Duct Pipe, 3 ft section",
            shape: :round,
            diameter: diameter.to_f,
            stock_length: 36.0,
            style: :snap_lock
          )
        end

        [4, 5, 6, 7, 8, 10, 12].each do |diameter|
          products << product(
            sku: "BDCP#{diameter}X60",
            family: :pipe,
            name: "#{diameter}\" Beaded Metal Duct Pipe, 5 ft section",
            shape: :round,
            diameter: diameter.to_f,
            stock_length: 60.0,
            style: :beaded
          )
        end

        [3, 4, 5, 6, 7, 8, 10, 12, 14].each do |diameter|
          products << product(
            sku: "CP#{diameter}X60",
            family: :pipe,
            name: "#{diameter}\" Round Metal Duct Pipe, 5 ft section",
            shape: :round,
            diameter: diameter.to_f,
            stock_length: 60.0,
            style: :snap_lock
          )
        end

        products.freeze
      end

      # ---- STRAIGHT RECTANGULAR DUCT -----------------------------------------
      RECTANGULAR_PIPES = [
        ["RD12X8X48",      12.0, 8.0,  48.0],
        ["RD14X8X48",      14.0, 8.0,  48.0],
        ["RD16X8X48",      16.0, 8.0,  48.0],
        ["RD24X8X48",      24.0, 8.0,  48.0],
        ["RD2.25X12X24",   12.0, 2.25, 24.0],
        ["RD3.25X10X36",   10.0, 3.25, 36.0],
        ["RD3.25X12X36",   12.0, 3.25, 36.0],
        ["RD3.25X14X36",   14.0, 3.25, 36.0],
        ["RD3.25X10X60",   10.0, 3.25, 60.0],
        ["RD3.25X12X60",   12.0, 3.25, 60.0],
        ["RD3.25X14X60",   14.0, 3.25, 60.0]
      ].map do |sku, width, height, stock_length|
        product(
          sku: sku,
          family: :pipe,
          name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" Rectangular Duct, #{stock_length.to_i / 12} ft section",
          shape: :rectangular,
          width: width,
          height: height,
          stock_length: stock_length,
          style: :half_section,
          notes: "Catalog product is sold in half sections; modeled geometry is the assembled rectangular duct."
        )
      end.freeze

      # ---- ELBOWS -------------------------------------------------------------
      # Product heights below are published assembled envelope heights. Catalog
      # mode places each elbow as a rigid 90-degree configured fitting. Round
      # elbows are physically adjustable products, but the route never deforms a
      # placed elbow to chase an arbitrary point.
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
          style: :four_gore_adjustable,
          notes: "Master Flow adjustable elbow; modeled in a fixed 90-degree installed configuration with four visible swivel/gore sections."
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
          style: :short_way_miter,
          notes: "Rigid short-way 90-degree stack elbow."
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
          style: :long_way_miter,
          notes: "Long-way rectangular stack elbow."
        )
      ].freeze

      # ---- TEES ---------------------------------------------------------------
      # All tee sizes listed in RESMF164. For T4/T5/T6/T8, published overall
      # envelope dimensions are included. T3 has exact nominal connector size
      # from the catalog; the retailer does not publish an assembled H/W/L table.
      ROUND_TEES = [
        ["T3X3X3", 3.0, nil,  nil, nil],
        ["T4X4X4", 4.0, 6.5,  4.0, 8.0],
        ["T5X5X5", 5.0, 10.0, 5.0, 10.0],
        ["T6X6X6", 6.0, 8.5,  6.0, 10.0],
        ["T8X8X8", 8.0, 10.0, 8.0, 12.0]
      ].map do |sku, diameter, h, w, l|
        product(
          sku: sku,
          family: :tee,
          name: "#{diameter.to_s.sub('.0','')}\" Round Tee",
          shape: :round,
          diameter: diameter,
          branch_diameter: diameter,
          outlet_diameter: diameter,
          angle_degrees: 90.0,
          overall: h ? { height: h, width: w, length: l } : nil,
          style: :full_flow_tee,
          notes: "Equal-diameter 90-degree full-flow tee."
        )
      end.freeze

      # ---- WYES ---------------------------------------------------------------
      # All five Master Flow wyes in the catalog are supported. Reducing wyes
      # are integral products: Y8X6X6 has an 8-inch inlet and two 6-inch outlets;
      # Y10X8X8 has a 10-inch inlet and two 8-inch outlets.
      ROUND_WYES = [
        ["Y4X4X4",   4.0,  4.0,  8.5,  11.0, 4.0],
        ["Y6X6X6",   6.0,  6.0, 11.75, 13.0, 6.0],
        ["Y8X6X6",   8.0,  6.0, 12.5,  15.0, 8.0],
        ["Y8X8X8",   8.0,  8.0, 16.0,  16.0, 8.0],
        ["Y10X8X8", 10.0,  8.0, 16.0,  16.0, 10.0]
      ].map do |sku, inlet, outlet, h, w, l|
        product(
          sku: sku,
          family: :wye,
          name: "#{inlet.to_s.sub('.0','')}\" to #{outlet.to_s.sub('.0','')}\" x #{outlet.to_s.sub('.0','')}\" Round Wye",
          shape: :round,
          diameter: inlet,
          outlet_diameter: outlet,
          branch_diameter: outlet,
          angle_degrees: 45.0,
          overall: { height: h, width: w, length: l },
          style: inlet == outlet ? :equal_lateral : :integral_reducing_lateral,
          notes: "Integral Master Flow reducing lateral when inlet and outlet diameters differ."
        )
      end.freeze

      # ---- ROUND REDUCERS / INCREASERS ---------------------------------------
      ROUND_REDUCERS = [
        ["R4X3",    4.0,  3.0, 6.375],
        ["R5X4",    5.0,  4.0, 5.5],
        ["R6X4",    6.0,  4.0, 6.0],
        ["R6X5",    6.0,  5.0, 5.5],
        ["R7X4",    7.0,  4.0, 6.0],
        ["R7X6",    7.0,  6.0, 5.875],
        ["R8X6",    8.0,  6.0, 8.375],
        ["R8X7",    8.0,  7.0, 6.0],
        ["R10X8",  10.0,  8.0, 6.0],
        ["R12X10", 12.0, 10.0, 8.0],
        ["R14X12", 14.0, 12.0, 8.0]
      ].map do |sku, large, small, length|
        product(
          sku: sku,
          family: :transition,
          name: "#{large.to_s.sub('.0','')}\" to #{small.to_s.sub('.0','')}\" Round Reducer / Increaser",
          shape: :round,
          diameter: large,
          branch_diameter: small,
          transition_length: length,
          overall: { diameter: large, length: length },
          style: :hemmed_reducer
        )
      end.freeze

      # ---- STRAIGHT ROUND / RECTANGULAR STACK BOOTS --------------------------
      STACK_BOOTS = [
        ["SB12X2.25X6", 12.0, 2.25, 6.0, 10.0],
        ["SB10X3.25X4", 10.0, 3.25, 4.0, 10.0],
        ["SB10X3.25X5", 10.0, 3.25, 5.0, 7.0],
        ["SB10X3.25X6", 10.0, 3.25, 6.0, 6.0],
        ["SB10X3.25X7", 10.0, 3.25, 7.0, 6.0]
      ].map do |sku, width, height, diameter, length|
        product(
          sku: sku,
          family: :transition,
          name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" to #{diameter.to_s.sub('.0','')}\" Straight Stack Boot",
          shape: :mixed,
          width: width,
          height: height,
          diameter: diameter,
          transition_length: length,
          style: :straight_stack_boot,
          notes: "Straight-line round-to-rectangular stack boot."
        )
      end.freeze

      # ---- END COVERS ---------------------------------------------------------
      # RESMF164 contains three closely related cap families that map directly
      # to Simple Duct's existing end-cover behavior:
      #   * DC... / 8DC round duct caps
      #   * RDC... rectangular trunk duct caps
      #   * DC3.25X10 rectangular stack duct cap
      # Every catalog size in those families is represented here.
      END_COVERS = begin
        products = [
          ["DC3", 3.0],
          ["DC4", 4.0],
          ["DC5", 5.0],
          ["DC6", 6.0],
          ["8DC", 8.0]
        ].map do |sku, diameter|
          product(
            sku: sku,
            family: :end_cover,
            name: "#{diameter.to_s.sub('.0','')}\" Round Duct Cap",
            shape: :round,
            diameter: diameter,
            overall: { diameter: diameter, depth: [diameter * 0.16, 0.55].max },
            style: :round_duct_cap,
            notes: "Master Flow round duct termination cap."
          )
        end

        products.concat(
          [
            ["RDC12X8", 12.0, 8.0],
            ["RDC14X8", 14.0, 8.0],
            ["RDC16X8", 16.0, 8.0],
            ["RDC24X8", 24.0, 8.0]
          ].map do |sku, width, height|
            product(
              sku: sku,
              family: :end_cover,
              name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" Rectangular Duct Cap",
              shape: :rectangular,
              width: width,
              height: height,
              overall: { width: width, height: height, depth: 0.60 },
              style: :rectangular_duct_cap,
              notes: "Master Flow 28-gauge rectangular trunk duct termination cap."
            )
          end
        )

        products << product(
          sku: "DC3.25X10",
          family: :end_cover,
          name: "10\" x 3-1/4\" Rectangular Stack Duct Cap",
          shape: :rectangular,
          width: 10.0,
          height: 3.25,
          overall: { width: 10.25, height: 3.45, depth: 0.60 },
          style: :stack_cap,
          notes: "Shallow rectangular clean-out/termination cap; physical outside envelope is approximately 10.25 x 3.45 x 0.60 inches."
        )

        products.freeze
      end

      PRODUCTS = (
        ROUND_PIPES + RECTANGULAR_PIPES +
        ROUND_ELBOWS + RECTANGULAR_ELBOWS +
        ROUND_TEES + ROUND_WYES +
        ROUND_REDUCERS + STACK_BOOTS + END_COVERS
      ).freeze

      def products
        PRODUCTS
      end
    end
  end
end
