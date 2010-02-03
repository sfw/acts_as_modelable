# ActAsModelable
module ActionController
  module Acts
    module Modelable
      require 'digest/sha1'
      # include Classmethods into Base AR
      def self.included(base) # :nodoc:
        base.extend ClassMethods
      end
      
      module ClassMethods
        
        def acts_as_modelable(options = {}, &extension)
        
          # don't allow multiple calls
          return if self.included_modules.include?(ActionController::Acts::Modelable::ActMethods)

          #include ActMethods in AC
          send :include, ActionController::Acts::Modelable::ActMethods
          #ActionController::Base.send :include, ActionController::Acts::Modelable::ActMethods
          
          #cattr_accessor adds accessor methods
          cattr_accessor :exceptions, :transition_class_name, :transition_table_name, :state_class_name, :state_table_name,:include_session_fields
          
          self.exceptions = options[:exceptions]||[]
          self.include_session_fields = options[:include_session_fields]
          self.transition_class_name         = options[:transition_class_name]  || "Transition"
          self.transition_table_name         = options[:transition_table_name]  || "Transitions"
          self.state_class_name         = options[:state_class_name]  || "State"
          self.state_table_name         = options[:state_table_name]  || "States"
          
          
          #evaluate base code into the class using the plugin          
          class_eval <<-CLASS_METHODS           
            around_filter :wrap_transaction, :except=>:exceptions
          CLASS_METHODS
          
          #dynamic transition class creation
          const_set(transition_class_name, Class.new(ActiveRecord::Base)).class_eval do
             serialize :changes_hash, Hash
             serialize :params, Hash
          end
          
          #dynamc state class creation
          const_set(state_class_name, Class.new(ActiveRecord::Base)).class_eval do
            serialize :state_value, Hash
          end

          transition_class.set_table_name transition_table_name
          transition_class.send :include, options[:transition_extend]         if options[:transition_extend].is_a?(Module)
          state_class.set_table_name state_table_name
          state_class.send :include, options[:state_extend]         if options[:state_extend].is_a?(Module)
          
          
        end #end acts_as_modelable
        
      end #end ClassMethods
      
      module ActMethods
        def self.included(base) # :nodoc:
          base.extend ClassMethods
        end

        def initialize_transaction

          #get start state
          #TODO have to add session values to state
          current_state_value= get_state

          #add session if required
          if !self.include_session_fields.nil? 
            current_state_value[:session]={}
            self.include_session_fields.each do |f|
              #if null skip
              if !session[f].nil?
                #add to hash
                current_state_value[:session][f]=session[f]
                puts "STATE-SESSION: #{f} = > #{session[f]}"
              end #if
            end #do
          end#if
          
          current_state_id=nil
         
         
         # ISSUE there could be an issue with hash sorting. Ignore for now.
          
          @current_state=false
          #check existing states
          if self.class.state_class.exists?(:state_value_hash=>Digest::MD5.hexdigest(current_state_value.to_yaml))
             @current_state=self.class.state_class.find(:first,:conditions=>{:state_value_hash=>Digest::MD5.hexdigest(current_state_value.to_yaml)})
             current_state_id=@current_state.id
             logger.debug " : ( #{Time.now.to_s} - STATE-state found #{current_state_id} )"
          else
            @current_state=self.class.state_class.new
            @current_state.state_value = current_state_value
            @current_state.state_value_hash=Digest::MD5.hexdigest(current_state_value.to_yaml)
            @current_state.save
            current_state_id=@current_state.id
            logger.debug " : ( #{Time.now.to_s} - STATE-state made #{current_state_id} )"
          end
          
          
          #check transition
          @transition=false
          if self.class.transition_class.exists?(:state_id=>current_state_id,:params_hash=>Digest::MD5.hexdigest(params.to_yaml))
            @transition=self.class.transition_class.find(:first,:conditions=>{:state_id=>current_state_id,:params_hash=>Digest::MD5.hexdigest(params.to_yaml)})
            flash[:notice]= " : ( #{Time.now.to_s} - TRANS-found transition #{@transition.id} )"
          else
            @transition = self.class.transition_class.new
            @transition.state_id = current_state_id
            @transition.changes_hash={}
            @transition.params=params
            @transition.params_hash=Digest::MD5.hexdigest(params.to_yaml)
            @transition.save
            flash[:notice]=  " : ( #{Time.now.to_s} - TRANS-made transition #{@transition.id} )"
          end
          ActiveRecord::Base.send :trans_id, @transition.id
        end
        
        def finalize_transaction
          #add session if required.
          if !self.include_session_fields.nil?

            session_changes_hash={}
            #iterate session fields
            self.include_session_fields.each do |f|
              #if null skip
              if !session[f].nil?
                #check if the session field was in the start_state session hash
                if @current_state.state_value[:session].has_key?(f)
                  #yes, check to see if it's been changed
                  if !@current_state.state_value[:session][f]==session[f]
                    #if yes, add to temp hash
                    session_changes_hash[f.to_s]=session[f]
                    puts "SESSION: #{f} = > #{session[f]}"
                  end
                  # if no, continue
                else
                  #if key wasn't in start state session, add to changes
                  session_changes_hash[f.to_s]=session[f]
                end# if cs.sv.hk
                
              end# if s.nil
            end#if isf.do
            #only update record if not empty, avoid extra sql
            if !session_changes_hash.empty?
              #get values added from models
              @transition.reload
              #add session hash to :session index
              @transition.changes_hash[:session]=session_changes_hash
              #save
              @transition.save
            end #if sch.empt
          end #if sif.nil
        end #finalize transaction
        
        def wrap_transaction
          initialize_transaction
          yield 
          finalize_transaction
        end
        
        def get_state
          standing_state={}
          
          if !defined?(@@models)
            @@models=[]
            Dir.glob(RAILS_ROOT + '/app/models/*.rb').each { |file| require file }
            model_list = Object.subclasses_of(ActiveRecord::Base)
          
            model_list.each do |modl|
            
              #see if modl is included in model
              if !defined?(modl.is_modelable?)
                #if not skip to next
                next
              else
                @@models<<modl
              end
            end
          else
          end
          
            @@models.each do |mdl|
              #see if model is in state hash
              if !standing_state.has_key?(mdl.name)
                #if not, add it
                standing_state[mdl.name]={}
              end
            
            
              #get all objects of model type
              mdl_objects = mdl.all
            
              #iterate over all objects of modelable classes

              mdl_objects.each do |obj|
                
                #puts "Object inclusion, model: #{mdl.name} - id: #{obj.id}"
                #see if object is in state hash
                if !standing_state[mdl.name].has_key?(obj.id)
                  #if not, add it
                  standing_state[mdl.name][obj.id]={}
                end
              
                #push field values to hash
                state_hash=obj.class.object_state_hash(obj)
                state_hash.each do |key,value|
                  standing_state[mdl.name][obj.id][key]=value
                end
              
              end
    
            end
          #return completed state
           return standing_state
        end
        
        #protected section
        protected
        
        module ClassMethods
          
           # Returns an instance of the dynamic versioned model
           def transition_class
             const_get transition_class_name
           end
           
           # Returns an instance of the dynamic versioned model
           def state_class
             const_get state_class_name
           end
           
        end #end protected classmethods
        
      end#end ActMethods
      
    end #end Modelable
    
  end #end Acts
  
end #end AC

ActionController::Base.send :include, ActionController::Acts::Modelable