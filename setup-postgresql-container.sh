#!/bin/bash

CONTAINER_NAME="postgres-dev"
POSTGRES_USER="root"
POSTGRES_PASSWORD="root"
INITIAL_DB="postgres"
PG_PORT=5432
VOLUME_NAME="PGDATA"
IMAGE_NAME="postgres"

# Colors for highlighting
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
RESET="\033[0m"

clear

# Create container if it doesn't exist
if ! docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
  echo -e "${GREEN}🚀 Creating PostgreSQL container '${CONTAINER_NAME}'...${RESET}"
  docker run --name $CONTAINER_NAME \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -e POSTGRES_DB=$INITIAL_DB \
    -p $PG_PORT:5432 \
    -v $VOLUME_NAME:/var/lib/postgresql/data \
    -d $IMAGE_NAME
  sleep 2
else
  echo -e "${YELLOW}📦 Container already exists: ${CONTAINER_NAME}${RESET}"
fi

add_database() {
  read -p "📝 Enter new database name: " new_db
  if [[ -z "$new_db" ]]; then
    echo -e "${RED}❌ Database name cannot be empty.${RESET}"
    read -p "🔙 Press Enter to continue..."
    return
  fi

  echo -e "${GREEN}📡 Creating database \"$new_db\"...${RESET}"
  docker exec -u $POSTGRES_USER -e PGPASSWORD=$POSTGRES_PASSWORD $CONTAINER_NAME \
    psql -U $POSTGRES_USER -d $INITIAL_DB -c "CREATE DATABASE \"$new_db\";"
  echo -e "${GREEN}✔ Database created successfully.${RESET}"
  read -p "🔙 Press Enter to continue..."
}

list_databases() {
  echo -e "${CYAN}📚 Existing databases:${RESET}"
  docker exec -u $POSTGRES_USER -e PGPASSWORD=$POSTGRES_PASSWORD $CONTAINER_NAME \
    psql -U $POSTGRES_USER -d $INITIAL_DB -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" | sed '/^\s*$/d'
  echo
  read -p "🔙 Press Enter to continue..."
}

stop_container() {
  echo -e "${RED}🛑 Stopping container '${CONTAINER_NAME}'...${RESET}"
  docker stop $CONTAINER_NAME > /dev/null
  echo -e "${RED}✔ Container stopped.${RESET}"
  read -p "🔙 Press Enter to continue..."
}

menu_items=("Add new database" "List databases" "Stop container" "Exit")
actions=("add_database" "list_databases" "stop_container" "exit")

selected=0

draw_menu() {
  clear
  echo -e "${CYAN}🎛️  PostgreSQL Dev Menu${RESET}"
  echo -e "${YELLOW}Use ↑ ↓ to navigate and Enter to select${RESET}"
  echo
  for i in "${!menu_items[@]}"; do
    if [[ $i == $selected ]]; then
      echo -e "👉 ${GREEN}${menu_items[$i]}${RESET}"
    else
      echo "   ${menu_items[$i]}"
    fi
  done
}

while true; do
  draw_menu

  # Read key (1 or 3 bytes for arrows)
  IFS= read -rsn1 key
  if [[ $key == $'\x1b' ]]; then
    read -rsn2 -t 0.1 key # capture arrow sequence
  fi

  case $key in
    "[A") # up arrow
      ((selected--))
      ((selected < 0)) && selected=$((${#menu_items[@]} - 1))
      ;;
    "[B") # down arrow
      ((selected++))
      ((selected >= ${#menu_items[@]})) && selected=0
      ;;
    "") # Enter
      action=${actions[$selected]}
      if [[ $action == "exit" ]]; then
        echo -e "${YELLOW}👋 Exiting...${RESET}"
        break
      else
        clear
        $action
      fi
      ;;
  esac
done

