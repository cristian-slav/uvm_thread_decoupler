# uvm_thread_decoupler
Utility class to decouple a task from its caller process so that a call to kill() method of the parent process does not terminate the targeted task.

For details on this project please read the associated article <a href="http://cfs-vision.com/2023/02/08/how-to-decouple-threads-in-systemverilog/">How to Decouple Threads in SystemVerilog</a>

<h1>Integration Steps</h1>
These are the steps required to decouple a task called <i>encrypt()</i> from its caller process. 
<br/>The term <b>target task</b> refers to the task we want to decouple, which is in this case <i>encrypt()</i> task.
<h2>Step #1: Import uvm_thread_decoupler.sv File</h2>
<br/>Copy the file <a target="_black" href="https://github.com/cristian-slav/uvm_thread_decoupler/blob/main/sv/uvm_thread_decoupler.sv">uvm_thread_decoupler.sv</a> into your project and include it in the necessary package:
<pre><code>package cfs_enc_pkg;
  ...
  `include "uvm_thread_decoupler.sv"
  ...
endpackage</code></pre>
<h2>Step #2: Create an Instance of the uvm_thread_decoupler Class</h2>
Because uvm_thread_decoupler is a child of uvm_component, creating an instance of it must follow the same approach as with any other uvm_component:
<pre><code>class cfs_enc_model extends uvm_component;
  ...
  //Thread decoupler for handling the encrypt() task
  uvm_thread_decoupler encrypt_decoupler;
  ...
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    encrypt_decoupler = uvm_thread_decoupler::type_id::create("encrypt_decoupler", this);
  endfunction
  ...
endclass</code></pre>
<h2>Step #3: Connect the Target Task to the Thread Decoupler</h2>
We need to inform the uvm_thread_decoupler which task it needs to decouple from its parent’s process. This is done with the help of a TLM blocking put port.
<br/>First we need to declare a TLM blocking put port implementation with a relevant suffix. A good choice for the suffix would be the name of the task we want to decouple.
<pre><code>//Declare a blocking put port implementation for the encrypt() task
`uvm_blocking_put_imp_decl(_encrypt)</code></pre>
Next we need to create an instance of this port implementation:
<pre><code>class cfs_enc_model extends uvm_component;
  ...
  //Port connected the the process decoupler associated with encrypt() task
  uvm_blocking_put_imp_encrypt#(uvm_object, cfs_enc_model) port_encrypt_decoupler;
  ...
  function new(string name = "", uvm_component parent);
    super.new(name, parent);
    ...
    port_encrypt_decoupler = new("port_encrypt_decoupler", this);
  endfunction
  ...
endclass</code></pre>
uvm_thread_decoupler knows which task to decouple by calling that task in the put() implementation of the port:
<pre><code>class cfs_enc_model extends uvm_component;
  ...
  //Task associated with the put port of the thread decoupler
  virtual task put_encrypt(uvm_object arg);
    encrypt();
  endtask
  ...
endclass</code></pre>
Finally we need to connect this port implementation with the one from the uvm_thread_decoupler:
<pre><code>class cfs_enc_model extends uvm_component;
  ...
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ...      
    encrypt_decoupler.port_execute.connect(port_encrypt_decoupler);
  endfunction
  ...
endclass</code></pre>
<h2>Step #4: Substitute the Target Task Call With execute() Task</h2>
The <i>execute()</i> task from uvm_thread_decoupler is a task which consumes the same amount of time as our target task. 
<br/>Calling it instead of the target task has no effect on the overall functionality … except, of course, for the decoupling part:
<pre><code>class cfs_enc_model extends uvm_component implements cfs_enc_reset_handler;
  ...
  //Function called when the software started the encryption
  virtual function void sw_encryption_start(bit prev_value, bit next_value);
    fork
      begin
        //Replace the call to encrypt() with the call to execute()
        encrypt_decoupler.execute();
      end
    join_none
  endfunction
  ...
endclass</code></pre>
<h2>Step #5: Kill the <i>encrypt()</i> Task at the Correct Reset</h2>
We can still kill the <i>encrypt()</i> task at the correct reset via <i>handle_reset()</i> function of the uvm_thread_decoupler:
<pre><code>class cfs_enc_model extends uvm_component implements cfs_enc_reset_handler;
  ...
  virtual function void  handle_reset(uvm_phase phase, string kind);
    if(kind == "SYS") begin
      //Kill the encrypt() task
      encrypt_decoupler.handle_reset(phase, kind);
    end
    else if(kind == "HARD") begin
      ...
    end
    else begin
     `uvm_error("ERROR", $sformatf("Unknown reset kind: %0s", kind))
    end
  endfunction
  ...
endclass</code></pre>
