import uvm_pkg::*;
`include "uvm_macros.svh"

`include "svunit_defines.svh"
`include "svunit_uvm_mock_pkg.sv"
 import svunit_uvm_mock_pkg::*;


`uvm_blocking_put_imp_decl(_count_decoupler)

class cfs_count_arg extends uvm_object;
  
  int unsigned count_id;
  
  int unsigned start_value;
  
  int unsigned steps;
  
  int unsigned end_value;
  
  `uvm_object_utils(cfs_count_arg);
  
  function new(string name = "");
    super.new(name);
    
    count_id = get_inst_id();
  endfunction
  
endclass

// Mock model for containing the thread decoupler
class cfs_model extends uvm_scoreboard;
  
  //List of completed counts
  cfs_count_arg completed_counts[$];

  //Instance of the thread decoupler for task count()
  uvm_thread_decoupler decoupler_count;
  
  //Port connected the the process decoupler associated with count() task
  uvm_blocking_put_imp_count_decoupler#(uvm_object, cfs_model) port_count_decoupler;
      
  `uvm_component_utils(cfs_model)
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
    
    port_count_decoupler = new("port_count_decoupler", this);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    decoupler_count = uvm_thread_decoupler::type_id::create("decoupler_count", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    decoupler_count.port_execute.connect(port_count_decoupler);
  endfunction
  
  virtual task count(int unsigned id, int unsigned start_value, int unsigned steps, ref int unsigned end_value);
    end_value = start_value;
    
    `uvm_info("MODEL", $sformatf("Start count - id: %0d, start: %0d, steps: %0d", id, start_value, steps), UVM_NONE)
    
    for(int step = 0; step < steps; step++) begin
      end_value += 1;
      #(1ns);
    end
    
    begin
      cfs_count_arg completed_count = cfs_count_arg::type_id::create("completed_count");
      completed_count.count_id     = id;
      completed_count.start_value  = start_value;
      completed_count.steps        = steps;
      completed_count.end_value    = end_value;
      
      completed_counts.push_back(completed_count);
    end
    
    `uvm_info("MODEL", $sformatf("Ended count - id: %0d, start: %0d, steps: %0d, end: %0d", id, start_value, steps, end_value), UVM_NONE)
  endtask
  
  //Task associated with the put port of the thread decoupler
  virtual task put_count_decoupler(uvm_object arg);
    cfs_count_arg count_arg;
    
    if($cast(count_arg, arg) == 0) begin
      $fatal("Can not convert the argument");
    end
    
    count(count_arg.count_id, count_arg.start_value, count_arg.steps, count_arg.end_value);
  endtask
      
endclass

module uvm_thread_decoupler_unit_test;
  
  import svunit_pkg::svunit_testcase;

  string name = "uvm_thread_decoupler_ut";
  svunit_testcase svunit_ut;

  cfs_model model;
  
  // Build - runs once
  function void build();
    svunit_ut = new(name);
    model = cfs_model::type_id::create("model", null);
    
    svunit_deactivate_uvm_component(model);
  endfunction

  // Setup before each test
  task setup();
    svunit_ut.setup();
    
    svunit_activate_uvm_component(model);
    
    svunit_uvm_test_start();
  endtask

  // Teardown after each test
  task teardown();
    svunit_ut.teardown();
    
    svunit_uvm_test_finish();
    
    svunit_deactivate_uvm_component(model);
  endtask

  `SVUNIT_TESTS_BEGIN

    // Test that two threads running in parallel are executed correctly
    `SVTEST(two_threads_in_parallel)
      cfs_count_arg arg0 = cfs_count_arg::type_id::create("arg0");
      cfs_count_arg arg1 = cfs_count_arg::type_id::create("arg1");

      arg0.start_value = 0;
      arg0.steps       = 10;

      arg1.start_value = 5;
      arg1.steps       = 20;

      fork
        begin
          model.decoupler_count.execute(arg0);
        end
        begin
          model.decoupler_count.execute(arg1);
        end
      join


      //Check that at this point two counts where completed
      `FAIL_IF(model.completed_counts.size() != 2);

      //Check the arguments of the first thread
      `FAIL_UNLESS_EQUAL(arg0.count_id,                 model.completed_counts[0].count_id);
      `FAIL_UNLESS_EQUAL(arg0.start_value,              model.completed_counts[0].start_value);
      `FAIL_UNLESS_EQUAL(arg0.steps,                    model.completed_counts[0].steps);
      `FAIL_UNLESS_EQUAL(arg0.start_value + arg0.steps, model.completed_counts[0].end_value);

      //Check the arguments of the second thread
      `FAIL_UNLESS_EQUAL(arg1.count_id,                 model.completed_counts[1].count_id);
      `FAIL_UNLESS_EQUAL(arg1.start_value,              model.completed_counts[1].start_value);
      `FAIL_UNLESS_EQUAL(arg1.steps,                    model.completed_counts[1].steps);
      `FAIL_UNLESS_EQUAL(arg1.start_value + arg1.steps, model.completed_counts[1].end_value);
  
    `SVTEST_END

    // Test the logic to kill a thread in the middle
    `SVTEST(kill_thread)
      cfs_count_arg arg0 = cfs_count_arg::type_id::create("arg0");
      cfs_count_arg arg1 = cfs_count_arg::type_id::create("arg1");
      cfs_count_arg arg2 = cfs_count_arg::type_id::create("arg2");
  
      //ID of the thread to be killed
      int unsigned arg1_thread_id;

      arg0.start_value = 0;
      arg0.steps       = 100;

      arg1.start_value = 80;
      arg1.steps       = 100;

      arg2.start_value = 100;
      arg2.steps       = 100;
  
      //Clear results from previous test
      model.completed_counts.delete();

      fork
        begin
          model.decoupler_count.execute(arg0);
        end
        begin
          model.decoupler_count.execute_with_id(arg1, arg1_thread_id);
        end
        begin
          model.decoupler_count.execute(arg2);
        end
        begin
          #(20ns);
          
          //Make sure the thread is executing
          `FAIL_IF(model.decoupler_count.is_thread_id_pending(arg1_thread_id) == 1);
          `FAIL_IF(model.decoupler_count.is_thread_id_executing(arg1_thread_id) == 0);
          
          model.decoupler_count.kill_thread(arg1_thread_id);
          
          //Make sure the thread is removed completly
          `FAIL_IF(model.decoupler_count.is_thread_id_pending(arg1_thread_id) == 1);
          `FAIL_IF(model.decoupler_count.is_thread_id_executing(arg1_thread_id) == 1);
          
        end
      join


      //Check that at this point two counts where completed
      `FAIL_IF(model.completed_counts.size() != 2);

      //Check the arguments of the first thread
      `FAIL_UNLESS_EQUAL(arg0.count_id,                 model.completed_counts[0].count_id);
      `FAIL_UNLESS_EQUAL(arg0.start_value,              model.completed_counts[0].start_value);
      `FAIL_UNLESS_EQUAL(arg0.steps,                    model.completed_counts[0].steps);
      `FAIL_UNLESS_EQUAL(arg0.start_value + arg0.steps, model.completed_counts[0].end_value);

      //Check the arguments of the third thread
      `FAIL_UNLESS_EQUAL(arg2.count_id,                 model.completed_counts[1].count_id);
      `FAIL_UNLESS_EQUAL(arg2.start_value,              model.completed_counts[1].start_value);
      `FAIL_UNLESS_EQUAL(arg2.steps,                    model.completed_counts[1].steps);
      `FAIL_UNLESS_EQUAL(arg2.start_value + arg2.steps, model.completed_counts[1].end_value);

    `SVTEST_END

    // Test the logic to reset the thread decoupler in the middle
    `SVTEST(reset_decoupler)
      cfs_count_arg arg0 = cfs_count_arg::type_id::create("arg0");
      cfs_count_arg arg1 = cfs_count_arg::type_id::create("arg1");
      cfs_count_arg arg2 = cfs_count_arg::type_id::create("arg2");
  
      time branch0_end_time = -1;
      time branch1_end_time = -1;
      time branch2_end_time = -1;
      time branch3_end_time = -1;
  
      arg0.start_value = 0;
      arg0.steps       = 100;

      arg1.start_value = 80;
      arg1.steps       = 100;

      arg2.start_value = 100;
      arg2.steps       = 100;
  
      //Clear results from previous test
      model.completed_counts.delete();

      fork
        begin
          model.decoupler_count.execute(arg0);
          
          branch0_end_time = $time();
        end
        begin
          model.decoupler_count.execute(arg1);
          
          branch1_end_time = $time();
        end
        begin
          model.decoupler_count.execute(arg2);
          
          branch2_end_time = $time();
        end
        begin
          int unsigned thread_ids[$];
          #(40ns);
          
          model.decoupler_count.handle_reset(null);
          
          model.decoupler_count.get_pending_threads_ids(thread_ids);
          
          //Make sure that there is no pending thread
          `FAIL_IF(thread_ids.size() != 0);
          
          model.decoupler_count.get_executing_threads_ids(thread_ids);
          
          //Make sure that there is no executing thread
          `FAIL_IF(thread_ids.size() != 0);
          
          `FAIL_IF(model.completed_counts.size() != 0);
          
          branch3_end_time = $time();
        end
      join

      //Check that when the reset branch ended all the other three are ended
      `FAIL_IF(branch0_end_time != $time());
      `FAIL_IF(branch1_end_time != $time());
      `FAIL_IF(branch2_end_time != $time());
      `FAIL_IF(branch3_end_time != $time());
  
      //Start new threads after reset and make sure they end correctly
      begin
        cfs_count_arg arg0 = cfs_count_arg::type_id::create("arg0");
        cfs_count_arg arg1 = cfs_count_arg::type_id::create("arg1");
        cfs_count_arg arg2 = cfs_count_arg::type_id::create("arg2");
        cfs_count_arg arg3 = cfs_count_arg::type_id::create("arg3");

        arg0.start_value = 0;
        arg0.steps       = 120;

        arg1.start_value = 5;
        arg1.steps       = 110;

        arg2.start_value = 543;
        arg2.steps       = 100;

        arg3.start_value = 35;
        arg3.steps       = 90;

        fork
          begin
            model.decoupler_count.execute(arg0);
          end
          begin
            model.decoupler_count.execute(arg1);
          end
          begin
            model.decoupler_count.execute(arg2);
          end
          begin
            model.decoupler_count.execute(arg3);
          end
        join


        //Check that at this point two counts where completed
        `FAIL_IF(model.completed_counts.size() != 4);

        //Check the arguments of the first thread
        `FAIL_UNLESS_EQUAL(arg0.count_id,                 model.completed_counts[3].count_id);
        `FAIL_UNLESS_EQUAL(arg0.start_value,              model.completed_counts[3].start_value);
        `FAIL_UNLESS_EQUAL(arg0.steps,                    model.completed_counts[3].steps);
        `FAIL_UNLESS_EQUAL(arg0.start_value + arg0.steps, model.completed_counts[3].end_value);

        //Check the arguments of the second thread
        `FAIL_UNLESS_EQUAL(arg1.count_id,                 model.completed_counts[2].count_id);
        `FAIL_UNLESS_EQUAL(arg1.start_value,              model.completed_counts[2].start_value);
        `FAIL_UNLESS_EQUAL(arg1.steps,                    model.completed_counts[2].steps);
        `FAIL_UNLESS_EQUAL(arg1.start_value + arg1.steps, model.completed_counts[2].end_value);

        //Check the arguments of the third thread
        `FAIL_UNLESS_EQUAL(arg2.count_id,                 model.completed_counts[1].count_id);
        `FAIL_UNLESS_EQUAL(arg2.start_value,              model.completed_counts[1].start_value);
        `FAIL_UNLESS_EQUAL(arg2.steps,                    model.completed_counts[1].steps);
        `FAIL_UNLESS_EQUAL(arg2.start_value + arg2.steps, model.completed_counts[1].end_value);

        //Check the arguments of the forth thread
        `FAIL_UNLESS_EQUAL(arg3.count_id,                 model.completed_counts[0].count_id);
        `FAIL_UNLESS_EQUAL(arg3.start_value,              model.completed_counts[0].start_value);
        `FAIL_UNLESS_EQUAL(arg3.steps,                    model.completed_counts[0].steps);
        `FAIL_UNLESS_EQUAL(arg3.start_value + arg3.steps, model.completed_counts[0].end_value);

      end

    `SVTEST_END

     // Test that the original task, count(), is executing in the same amount of time as the execute() task
    `SVTEST(same_time_tasks)
      cfs_count_arg arg0 = cfs_count_arg::type_id::create("arg0");

      time branch0_end_time = -1;
      time branch1_end_time = -1;
      int unsigned branch0_end_value;
  
      arg0.start_value = 0;
      arg0.steps       = 15;

      //Clear results from previous test
      model.completed_counts.delete();

      fork
        begin
          model.count(arg0.count_id, arg0.start_value, arg0.steps, branch0_end_value);
          branch0_end_time = $time();
        end
        begin
          model.decoupler_count.execute(arg0);
          branch1_end_time = $time();
        end
      join

      `FAIL_IF(branch0_end_time != $time());
      `FAIL_IF(branch1_end_time != $time());

      //Check that at this point two counts where completed
      `FAIL_IF(model.completed_counts.size() != 2);

      //Check the arguments of the first thread
      `FAIL_UNLESS_EQUAL(arg0.count_id,                 model.completed_counts[0].count_id);
      `FAIL_UNLESS_EQUAL(arg0.start_value,              model.completed_counts[0].start_value);
      `FAIL_UNLESS_EQUAL(arg0.steps,                    model.completed_counts[0].steps);
      `FAIL_UNLESS_EQUAL(arg0.start_value + arg0.steps, model.completed_counts[0].end_value);

      //Check the arguments of the second thread
      `FAIL_UNLESS_EQUAL(arg0.count_id,                 model.completed_counts[1].count_id);
      `FAIL_UNLESS_EQUAL(arg0.start_value,              model.completed_counts[1].start_value);
      `FAIL_UNLESS_EQUAL(arg0.steps,                    model.completed_counts[1].steps);
      `FAIL_UNLESS_EQUAL(arg0.start_value + arg0.steps, model.completed_counts[1].end_value);
  
    `SVTEST_END

  `SVUNIT_TESTS_END
  
endmodule
