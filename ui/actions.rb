module DuctExtension
  module UIActions
    module_function

    def draw_duct
      Sketchup.active_model.select_tool(Tool::DuctTool.new)
    end

    def resize_selection
      model = Sketchup.active_model
      Services::SelectionResizeService.run(
        model: model,
        network: DuctExtension.network_for_model(model)
      )
    end

    def add_reducer
      Sketchup.active_model.select_tool(Tool::ReducerTool.new)
    end

    def clear_duct_data
      result = ::UI.messagebox(
        "This will clear all stored duct connection data from this model for performance purposes.\n\n" \
        "The 3D duct geometry will remain unchanged, but old ducts will no longer snap as editable duct pieces.\n\n" \
        "Continue?",
        MB_YESNO
      )
      return false unless result == IDYES

      model = Sketchup.active_model
      Services::NetworkClearService.clear_model_data(
        model,
        DuctExtension.network_for_model(model)
      )
      ::UI.messagebox("Duct data cleared. Geometry was left unchanged.")
      true
    end
  end
end
