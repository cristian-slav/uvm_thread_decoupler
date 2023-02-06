`ifndef UVM_THREAD_DECOUPLER_SV
  `define UVM_THREAD_DECOUPLER_SV

  //Information regarding one single thread handled by the thread decoupler.
  class uvm_thread_decoupler_info extends uvm_object;
    
    //Next process ID
    local static int unsigned next_thread_id;
    
    //Thread ID - unique for each process
    local int unsigned thread_id;
    
    //Thread argument
    local uvm_object thread_arg;
    
    //Reference to the process process
    local process thread_process;

    `uvm_object_utils(uvm_thread_decoupler_info)
    
    function new(string name = "");
      super.new(name);
      
      thread_id      = next_thread_id;
      next_thread_id = next_thread_id + 1;
    endfunction
    
    //Getter for the process ID
    function int unsigned get_thread_id();
      return thread_id;
    endfunction
    
    //Setter for process argument
    virtual function void set_thread_arg(uvm_object value);
      this.thread_arg = value;
    endfunction
    
    //Getter for process argument
    virtual function uvm_object get_thread_arg();
      return thread_arg;
    endfunction
    
    //Setter for the process reference of the actual process/thread executing
    function void set_thread_process(process value);
      if(this.thread_process != null) begin
        `uvm_fatal("THREAD_DECOUPLER_USAGE_ERROR", "Can not change the reference to the process process")
      end
    
      if(value == null) begin
        `uvm_fatal("THREAD_DECOUPLER_USAGE_ERROR", "Can not set a null reference to the process process")
      end
      
      thread_process = value;
    endfunction
    
    //Getter for the process reference of the actual process/thread executing
    function process get_thread_process();
      return thread_process;
    endfunction
    
  endclass

  //Thread decoupler.
  //This class allows a user to associate to it a process (e.g. a task)
  //which will be executed in a different process than the caller.
  class uvm_thread_decoupler extends uvm_component;
    
    //Put port connected to the actual task to be executed
    uvm_blocking_put_port#(uvm_object) port_execute;
    
    //List of pending threads
    local uvm_thread_decoupler_info pending_threads[$];
    
    //List of executing threads
    local uvm_thread_decoupler_info executing_threads[$];
    
    //Event emitted when a thread is started
    local event thread_started;
    
    //Event emitted when a thread is ended
    local event thread_ended;
    
    //Main process
    local process process_main;
    
    //Processes associated with execute_with_id()
    //The key is the thread ID
    local process processes_execute_with_id[int unsigned];
    
    `uvm_component_utils(uvm_thread_decoupler)
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      port_execute = new("port_execute", this);
    endfunction
    
    //Determine if a process ID is in a thread info list
    protected virtual function bit is_thread_id_in_list(int unsigned thread_id, ref uvm_thread_decoupler_info l[$]);
      bit found_it = 0;
          
      foreach(l[i]) begin
        if(l[i].get_thread_id() == thread_id) begin
          found_it = 1;
          break;
        end
      end
      
      return found_it;
    endfunction
    
    //Determine if a thread ID is pending
    virtual function bit is_thread_id_pending(int unsigned thread_id);
      return is_thread_id_in_list(thread_id, pending_threads);
    endfunction
    
    //Determine if a thread ID is executing
    virtual function bit is_thread_id_executing(int unsigned thread_id);
      return is_thread_id_in_list(thread_id, executing_threads);
    endfunction
    
    //Task to execute the decoupled thread.
    //The task also returns, through reference argument, the thread ID.
    //The thread ID can be used to kill the thread, when it is executing.
    virtual task execute_with_id(uvm_object arg = null, ref int unsigned thread_id);
      fork
        begin
          process p = process::self();
          
          //Wrap the argument in a different class to avoid the possibility of a user
          //to pass null argument or even the same argument.
          uvm_thread_decoupler_info info = uvm_thread_decoupler_info::type_id::create("info");
          info.set_thread_arg(arg);

          thread_id = info.get_thread_id();
          
          processes_execute_with_id[thread_id] = p;

          ->thread_started;

          pending_threads.push_back(info);

          //Wait for the thread to be moved away from pending
          while(is_thread_id_pending(info.get_thread_id()) == 1) begin
            uvm_wait_for_nba_region();
          end

          //Wait for the thread to be executed
          while(1) begin
            if(is_thread_id_executing(info.get_thread_id()) == 1) begin
              @(thread_ended);
            end

            if(is_thread_id_executing(info.get_thread_id()) == 0) begin
              break;
            end
          end
          
          processes_execute_with_id.delete(thread_id);
        end
      join
    endtask
    
    //Task to execute the decoupled thread
    virtual task execute(uvm_object arg = null);
      int unsigned thread_id;
      
      execute_with_id(arg, thread_id);
    endtask
    
    //Get the index of the executing thread, by ID
    protected virtual function int get_executing_thread_index(int unsigned id);
      int index = -1;
            
      foreach(executing_threads[i]) begin
        if(executing_threads[i].get_thread_id() == id) begin
          index = i;
          break;
        end
      end
      
      return index;
    endfunction
    
    //Spawn a new thread
    protected virtual function void spawn_thread(uvm_thread_decoupler_info info);
      executing_threads.push_back(info);
      
      fork
        begin
          info.set_thread_process(process::self());
          
          port_execute.put(info.get_thread_arg());
          
          begin
            int index = get_executing_thread_index(info.get_thread_id());
            
            if(index == -1) begin
              `uvm_fatal("THREAD_DECOUPLER", $sformatf("Can not find process ID 'h%0x in the list of executing processs", info.get_thread_id()))
            end
            
            executing_threads.delete(index);
            
            ->thread_ended;
          end
        end
      join_none
    endfunction
    
    //Get the IDs of all the pending threads
    virtual function void get_pending_threads_ids(ref int unsigned ids[$]);
      foreach(pending_threads[i]) begin
        ids.push_back(pending_threads[i].get_thread_id());
      end
    endfunction
    
    //Get the IDs of all the executing threads
    virtual function void get_executing_threads_ids(ref int unsigned ids[$]);
      foreach(executing_threads[i]) begin
        ids.push_back(executing_threads[i].get_thread_id());
      end
    endfunction
    
    //Kill executing thread, by ID
    virtual function void kill_thread(int unsigned id);
      int index = get_executing_thread_index(id);
      
      if(index != -1) begin
        uvm_thread_decoupler_info info = executing_threads[index];
        process thread_process         = info.get_thread_process();
        
        if(thread_process == null) begin
          `uvm_error("THREAD_DECOUPLER", $sformatf("The process associated with thread ID %0d is null", info.get_thread_id()))
        end
        else begin
          thread_process.kill();
          executing_threads.delete(index);
          ->thread_ended;
        end
      end  
    endfunction
    
    //Handle reset
    virtual function void handle_reset(uvm_phase phase, string kind = "HARD");
      if(process_main != null) begin
        process_main.kill();
        
        process_main = null;
      end
      
      foreach(processes_execute_with_id[key]) begin
        processes_execute_with_id[key].kill();
        processes_execute_with_id.delete(key);
      end
      
      pending_threads.delete();
      executing_threads.delete();
    endfunction
    
    virtual task run_phase(uvm_phase phase);
      forever begin
        fork
          begin
            process_main = process::self();
            
            forever begin
              if(pending_threads.size() == 0) begin
                @(thread_started);
              end

              spawn_thread(pending_threads.pop_front());
            end
          end
        join
      end
    endtask
    
  endclass

`endif