module Pandora
  module Model
    # Helper class to define, extend Pandora object classes
    # with xml document element
    class PandoraClass

      # Initialize helper with xml element
      def initialize(element)
        @element                       = element
        @fields                        = []

        # Strings
        @pan_obj_name              = element.name
        @pan_obj_parent_class_name = element.attributes['parent']

        # Constants
        @pan_obj_class             = self.class.by_name element.name
        @pan_obj_parent_class      = self.class.by_name element.attributes['parent']
      end

      # Check if pandora object class is already defined
      def defined?
        @pan_obj_class.nil?
      end

      # Define Pandora object class for current element
      def define
        Pandora.logger.debug
          "Defining class #{@pan_obj_class} < #{@pan_obj_parent_class} for element #{@pan_obj_name}"

        if @pan_obj_parent_class_name.present? && !pan_obj_parent_class
          Pandora.logger.warn "Parent class is not defined, ignoring"
        end
      end

      # Class methods
      class << self

        # Get class constant if it exists, nil otherwise
        def by_name(name)
          Pandora::Model.const_defined? name ? Pandora::Model.const_get(name) : nil
        end

        # Return Pandora::Model::Panobject constant
        def panobject
          Pandora::Model::Panobject
        end

      end

    end
  end
end