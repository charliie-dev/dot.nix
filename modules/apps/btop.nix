{
  btop = {
    enable = true;
    settings = {
      #* Set to True to enable "h,j,k,l,g,G" keys for directional control in lists.
      #* Conflicting keys for h:"help" and k:"kill" is accessible while holding shift.
      vim_keys = true;

      #* Update time in milliseconds, recommended 2000 ms or above for better sample times for graphs.
      update_ms = 100;

      #* Show processes as a tree.
      proc_tree = true;

      #* Use a darkening gradient in the process list.
      proc_gradient = false;

      log_level = "WARNING";
    };
    # extraConfig = ''

    # '';
  };
}
