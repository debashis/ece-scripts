#! /usr/bin/env bash

# by tkj@vizrt.com

print_h2_header "Operating system"

print_h3_header "Kernel"
print_pre_text $(uname -a)

print_h3_header "Distribution"
print_pre_text "$(lsb_release -a 2>/dev/null)" \
  $(cat /etc/redhat-release 2>/dev/null)

if [ $verbose -eq 1 ]; then
  print_h3_header "Installed packages"
  if [ $(which dpkg)x != "x" ]; then
    print_pre_text "$(dpkg -l 2>/dev/null)"
  elif [ $(which rpm)x != "x" ]; then
    print_pre_text "$(rpm -qa | sort 2>/dev/null)"
  fi
fi

print_h3_header "Timezone"
print_un_ordered_list_start
time_zone_file_list="/etc/timezone /etc/sysconfig/clock"
for el in $time_zone_file_list; do
  if [ -r $el ]; then
    print_list_item "$(cat $el) (from $el)"
  fi
done

if [ -n "$TZ" ]; then
  print_list_item "$(echo $TZ) (from ${USER}'s environment variable)"
fi
print_un_ordered_list_end


print_h3_header "Last Boot"
print_pre_text "$(who -b | sed -e 's/[a-z]*//g' -e 's/^[ ]*//g')"

# of the h2
print_section_end

