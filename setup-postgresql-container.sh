#!/bin/bash

CONTAINER_NAME="postgresql-dev"
POSTGRES_USER="root"
POSTGRES_PASSWORD="root"
INITIAL_DB="devdb"
PG_PORT=5432
VOLUME_NAME="pgdata_postgres_dev"
IMAGE_NAME="postgres"

# Colors
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
RESET="\033[0m"

wait_for_postgres() {
  echo -e "${YELLOW}⏳ Waiting for PostgreSQL to be ready...${RESET}"
  for i in {1..30}; do  # Aumentado de 10 para 30 tentativas
    if sudo docker exec $CONTAINER_NAME pg_isready -U $POSTGRES_USER > /dev/null 2>&1; then
      echo -e "${GREEN}✔ PostgreSQL is ready.${RESET}"
      return 0
    fi
    sleep 1
  done
  echo -e "${RED}❌ PostgreSQL is not responding.${RESET}"
  return 1
}


ensure_initial_db_exists() {
  sudo docker exec -u $POSTGRES_USER -e PGPASSWORD=$POSTGRES_PASSWORD $CONTAINER_NAME \
    psql -U $POSTGRES_USER -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$INITIAL_DB';" | grep -q 1 || \
    sudo docker exec -u $POSTGRES_USER -e PGPASSWORD=$POSTGRES_PASSWORD $CONTAINER_NAME \
    psql -U $POSTGRES_USER -d postgres -c "CREATE DATABASE $INITIAL_DB;"
}

add_database() {
  read -p "📝 Enter new database name: " new_db
  if [[ -z "$new_db" ]]; then
    echo -e "${RED}❌ Database name cannot be empty.${RESET}"
    read -p "🔙 Press Enter to continue..."
    return
  fi

  echo -e "${GREEN}📡 Creating database \"$new_db\"...${RESET}"
  sudo docker exec -u $POSTGRES_USER -e PGPASSWORD=$POSTGRES_PASSWORD $CONTAINER_NAME \
    psql -U $POSTGRES_USER -d $INITIAL_DB -c "CREATE DATABASE \"$new_db\";"
  echo -e "${GREEN}✔ Database created successfully.${RESET}"
  read -p "🔙 Press Enter to continue..."
}

list_databases() {
  if ! is_container_running; then
    echo -e "${RED}⚠️ Container is not running.${RESET}"
    read -p "🔙 Press Enter to continue..."
    return
  fi

  if ! sudo docker exec $CONTAINER_NAME pg_isready -U $POSTGRES_USER > /dev/null 2>&1; then
    echo -e "${YELLOW}⏳ Container is running, but PostgreSQL is still starting up...${RESET}"
    read -p "🔙 Press Enter to continue..."
    return
  fi

  echo -e "${CYAN}📚 Existing databases:${RESET}"
  sudo docker exec -u $POSTGRES_USER -e PGPASSWORD=$POSTGRES_PASSWORD $CONTAINER_NAME \
    psql -U $POSTGRES_USER -d $INITIAL_DB -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" | sed '/^\s*$/d'
  echo
  read -p "🔙 Press Enter to continue..."
}

start_container() {
  if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo -e "${GREEN}🚀 Creating and starting PostgreSQL container '${CONTAINER_NAME}'...${RESET}"
    if ! sudo docker run --name $CONTAINER_NAME \
      -e POSTGRES_USER=$POSTGRES_USER \
      -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
      -p $PG_PORT:5432 \
      -v $VOLUME_NAME:/var/lib/postgresql/data \
      -d $IMAGE_NAME; then
      echo -e "${RED}❌ Failed to start the container. Showing logs (if any):${RESET}"
      sudo docker logs $CONTAINER_NAME || echo -e "${RED}⚠️ No logs available.${RESET}"
      read -p "🔙 Press Enter to continue..."
      return
    fi
  else
    echo -e "${GREEN}🔄 Starting existing container '${CONTAINER_NAME}'...${RESET}"
    if ! sudo docker start $CONTAINER_NAME; then
      echo -e "${RED}❌ Failed to start the container. Showing logs (if any):${RESET}"
      sudo docker logs $CONTAINER_NAME || echo -e "${RED}⚠️ No logs available.${RESET}"
      read -p "🔙 Press Enter to continue..."
      return
    fi
  fi

  if wait_for_postgres; then
    ensure_initial_db_exists
  else
    echo -e "${RED}⚠️ PostgreSQL did not become ready. Showing logs:${RESET}"
    sudo docker logs $CONTAINER_NAME
  fi

  read -p "🔙 Press Enter to continue..."
}

stop_container() {
  echo -e "${RED}🛑 Stopping and removing container '${CONTAINER_NAME}'...${RESET}"
  sudo docker stop $CONTAINER_NAME > /dev/null
  sudo docker rm $CONTAINER_NAME > /dev/null
  sudo docker volume rm $VOLUME_NAME > /dev/null
  echo -e "${RED}✔ Container and data removed.${RESET}"
  read -p "🔙 Press Enter to continue..."
}

is_container_running() {
  sudo docker ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"
}

is_container_existing() {
  sudo docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"
}

selected=0

draw_menu() {
  clear
  echo -e "${CYAN}🎛️  PostgreSQL Dev Menu${RESET}"
  echo -e "${YELLOW}Use ↑ ↓ to navigate and Enter to select${RESET}"
  echo

  menu_items=("Add new database" "List databases" "Exit")
  actions=("add_database" "list_databases" "exit")

  if is_container_running; then
    menu_items=("Stop container" "${menu_items[@]}")
    actions=("stop_container" "${actions[@]}")
  else
    menu_items=("Start container" "${menu_items[@]}")
    actions=("start_container" "${actions[@]}")
  fi

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

  IFS= read -rsn1 key
  if [[ $key == $'\x1b' ]]; then
    read -rsn2 -t 0.1 key
  fi

  case $key in
    "[A") ((selected--)); ((selected < 0)) && selected=$((${#menu_items[@]} - 1)) ;;
    "[B") ((selected++)); ((selected >= ${#menu_items[@]})) && selected=0 ;;
    "")
      action=${actions[$selected]}
      if [[ $action == "exit" ]]; then
        echo -e "${YELLOW}👋 Exiting...${RESET}"
        break
      elif ! is_container_running && [[ $action != "start_container" ]]; then
        echo -e "${RED}⚠️ Container is not running. Please start it first.${RESET}"
        read -p "🔙 Press Enter to return..."
      else
        clear
        $action
      fi
      ;;
  esac
done

