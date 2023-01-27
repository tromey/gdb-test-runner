package require Tk

set progname "dejarunner"

if {![file exists site.exp]} {
  puts "$progname must be run in the testsuite build directory"
  exit 1
}

# This will define srcdir and tool.
source site.exp

if {[llength $argv] == 0} {
  set argv [list ${tool}.*/*.exp]
}
set all_files [lsort [glob -tails -directory $srcdir {*}${argv}]]
set saved_all_files $all_files

set ncpus [exec nproc]

tk appname $progname
wm withdraw .

toplevel .main -class $progname
wm geometry .main =1000x750
wm title .main $progname
wm iconname .main $progname
bind .main <Destroy> exit

ttk::labelframe .main.progress -text "Progress"
pack .main.progress -side top -fill both -padx 4 -pady 4

set jobs_completed 0
set jobs_running 0
ttk::progressbar .main.progress.bar -maximum [llength $all_files] \
  -mode determinate -variable jobs_completed
pack .main.progress.bar -side top -fill both -padx 4 -pady 4

ttk::labelframe .main.tasks -text "Current Tasks"
pack .main.tasks -side top -fill both -expand true -padx 4 -pady 4

for {set i 0} {$i < $ncpus} {incr i} {
  set job_state($i) ""
  set label [label .main.tasks.l$i -anchor w -textvariable job_state($i)]
  pack $label -side top -fill x -anchor w
}

ttk::labelframe .main.results -text "Results"
pack .main.results -side top -fill both -expand true -padx 4 -pady 4

# LOL.
set states {
  "expected passes"
  "unexpected failures"
  "expected failures"
  "known failures"
  "untested testcases"
  "unresolved testcases"
  "unsupported tests"
  "paths in test names"
  "duplicate test names"
}

set row 0
foreach state $states {
  set state_count($state) 0

  label .main.results.label$state -text $state -anchor w
  grid .main.results.label$state -sticky ne -column 0 -row $row

  label .main.results.num$state -textvariable state_count($state) -anchor e \
    -width 11
  grid .main.results.num$state -sticky nw -column 1 -row $row

  incr row
}

ttk::labelframe .main.buttons -text ""
pack .main.buttons -side top -fill x -padx 4 -pady 4

set go_button [button .main.buttons.go -text Go -command go]
pack .main.buttons.go -side top -padx 4 -pady 4

proc accept_output {jobno channel} {
  if {[chan gets $channel line] == -1} {
    # Might not really be EOF.
    if {[chan eof $channel]} {
      global jobs_completed jobs_running
      incr jobs_completed
      incr jobs_running -1
      catch {chan close $channel}
      start_new_test $jobno
    }
  } elseif {[regexp "^# of (\[a-z \]*\[a-z\])\[ \t\]+(\[0-9\]+)$" \
	       $line ignore name num]} {
    global state_count
    incr state_count($name) $num
  }
}

proc start_new_test {jobno} {
  global all_files job_state jobs_running

  if {[llength $all_files] == 0} {
    set job_state($jobno) "DONE"
    global go_button
    if {$jobs_running == 0} {
      $go_button configure -state active
    }
    return
  }

  set expfile [lindex $all_files 0]
  set all_files [lreplace $all_files 0 0]

  set job_state($jobno) $expfile
  incr jobs_running

  # EXPFILE is gdb.x/y.exp and we want outputs/gdb.x/y
  set outdir outputs/[file rootname $expfile]
  file mkdir $outdir

  set fd [open "| runtest GDB_PARALLEL=yes --outdir $outdir $expfile"]
  chan configure $fd -blocking 0 -buffering line
  chan event $fd readable [list accept_output $jobno $fd]
}

proc go {} {
  global ncpus go_button state_count
  $go_button configure -state disabled

  foreach name [array names state_count] {
    set state_count($name) 0
  }

  global all_files saved_all_files
  set all_files $saved_all_files

  for {set i 0} {$i < $ncpus} {incr i} {
    start_new_test $i
  }
}
