# ActAsModelable
module ActiveRecord
  module Acts
    module Modelable
      #CALLBACKS = [:object_state_hash]
      # include Classmethods into Base AR
      def self.included(base) # :nodoc:
        base.extend ClassMethods
      end
      
      module ClassMethods
        
        def acts_as_modelable(options = {}, &extension)

          # don't allow multiple calls
          return if self.included_modules.include?(ActiveRecord::Acts::Modelable::ActMethods)

          #include ActMethods in AR
          send :include, ActiveRecord::Acts::Modelable::ActMethods
          
          #cattr_accessor adds accessor methods
          cattr_accessor :implicit_observed_fields, :explicit_observed_fields, :transition_class_name, :transition_table_name
          
          self.implicit_observed_fields = options[:implicit_observed_fields]  || []
          self.explicit_observed_fields = options[:explicit_observed_fields]  || self.column_names - (self.implicit_observed_fields | ["created_at","updated_at"])
          self.transition_class_name         = options[:class_name]  || "Transition"
          self.transition_table_name         = options[:table_name]  || "Transitions"
          
          
          #evaluate base code into the class using the plugin
          class_eval <<-CLASS_METHODS
            after_validation_on_create :aam_on_create
            after_validation_on_update :aam_on_update
            before_destroy :aam_on_destroy
      
          CLASS_METHODS
          
          #hack for console usage
          if !defined?(@@transid)
            self.trans_id(0)
          end
          logger.debug "hello="+ self.transid.to_s
          
          #dynamic transition class creation
          const_set(transition_class_name, Class.new(ActiveRecord::Base)).class_eval do
              serialize :changes_hash, Hash
              serialize :params, Hash
          end

          transition_class.set_table_name transition_table_name
          transition_class.send :include, options[:extend]         if options[:extend].is_a?(Module)
          
        end #end acts_as_modelable
        
        def trans_id(tid)
          @@transid=tid
        end

        def transid
          @@transid
        end
        

        
      end #end ClassMethods
      
      module ActMethods
        def self.included(base) # :nodoc:
          base.extend ClassMethods
        end
        
        def aam_on_create
          #check if changes is blank, skip unnecessary steps
          if self.changes.empty?
            return
          end
          
          transition = self.class.transition_class.find(self.class.transid)

          #setup hash
          #class
          if !transition.changes_hash.has_key?(self.class.to_s)
            transition.changes_hash[self.class.to_s]={}
          end
          
          #object
          if !transition.changes_hash[self.class.to_s].has_key?(self.id)
            transition.changes_hash[self.class.to_s][self.id]={}
          end
          
          #implicit
          if !transition.changes_hash[self.class.to_s][self.id].has_key?(:implicit)
            transition.changes_hash[self.class.to_s][self.id][:implicit]=[]
          end
          
          #explicit
          if !transition.changes_hash[self.class.to_s][self.id].has_key?(:explicit)
            transition.changes_hash[self.class.to_s][self.id][:explicit]={}
          end
          
          self.changes.each{|c|
            #if a changes relates to an implicit field
            if implicit_observed_fields.include?(c[0])
              if !c[1].nil?
                transition.changes_hash[self.class.to_s][self.id][:implicit]<<c[0]
              end
              
            #if a change relates to an explicit field
            elsif explicit_observed_fields.include?(c[0])
              transition.changes_hash[self.class.to_s][self.id][:explicit][c[0]]=c[1]
            end
            
          }
          
          #set variable to tell process type
          transition.changes_hash[self.class.to_s][self.id]["__aam_type"]="create"
          transition.save
        end
        
        def aam_on_destroy
          
          transition = self.class.transition_class.find(self.class.transid)
          
          #need to add implicit/explicit subs
          #iterate over impl/exp and put fields into db

          #setup hash
          #class
          if !transition.changes_hash.has_key?(self.class.to_s)
            transition.changes_hash[self.class.to_s]={}
          end
          
          #object
          if !transition.changes_hash[self.class.to_s].has_key?(self.id)
            transition.changes_hash[self.class.to_s][self.id]={}
          end
          #set variable to tell process type
          transition.changes_hash[self.class.to_s][self.id]["__aam_type"]="delete"
          transition.save
        end
        
        def aam_on_update          
          
          #check if changes is blank, skip unnecessary steps
          if self.changes.empty?
            return
          end
          
          transition = self.class.transition_class.find(self.class.transid)
          
          #need to add implicit/explicit subs
          #iterate over impl/exp and put fields into db

          #setup hash
          #class
          if !transition.changes_hash.has_key?(self.class.to_s)
            transition.changes_hash[self.class.to_s]={}
          end
          
          #object
          if !transition.changes_hash[self.class.to_s].has_key?(self.id)
            transition.changes_hash[self.class.to_s][self.id]={}
          end
          
          #implicit
          if !transition.changes_hash[self.class.to_s][self.id].has_key?(:implicit)
            transition.changes_hash[self.class.to_s][self.id][:implicit]=[]
          end
          
          #explicit
          if !transition.changes_hash[self.class.to_s][self.id].has_key?(:explicit)
            transition.changes_hash[self.class.to_s][self.id][:explicit]={}
          end
          
          self.changes.each{|c|
            #if a changes relates to an implicit field
            #todo check for blank
            if implicit_observed_fields.include?(c[0])
              transition.changes_hash[self.class.to_s][self.id][:implicit]<<c[0]
            #if a change relates to an explicit field
            elsif explicit_observed_fields.include?(c[0])
              transition.changes_hash[self.class.to_s][self.id][:explicit][c[0]]=c[1]
            end
            
          }
          
          #set variable to tell process type
          transition.changes_hash[self.class.to_s][self.id]["__aam_type"]="update"
          transition.save

        end
        

        
        #start of protected
        protected
        
        module ClassMethods
          
          # return has of the object
          def object_state_hash(ov)
            state_hash={:implicit=>[],:explicit=>{}}
            #implicit fields
            self.implicit_observed_fields.each{|f|
                if !eval("ov.#{f}").nil?
                  state_hash[:implicit]<<f.to_s
                end
            }

            #explicit fields
            self.explicit_observed_fields.each{|f|
              state_hash[:explicit][f.to_s]=eval("ov.#{f}")                   
            }
            
             return state_hash
          end
          
           # Returns an instance of the dynamic versioned model
           def transition_class
             const_get transition_class_name
           end
           
           def is_modelable?
              true
           end 
           
        end #end protected classmethods

      end#end ActMethods
      
    end #end Modelable
    
  end #end Acts
  
end #end AR

ActiveRecord::Base.send :include, ActiveRecord::Acts::Modelable
