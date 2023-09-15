#!/bin/bash
SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

classes=1

# Activity
if classes -eq 1
then
  python $HOME/.config/qtile/activity.py $SCRIPTPATH/schedule.txt &
else
  python $HOME/.config/qtile/activity.py &  # Not in classes anymore
fi

# Break
$HOME/.config/qtile/break.sh &
