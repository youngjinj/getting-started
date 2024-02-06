#include <iostream> 
#include <string> // the C++ Standard String Class

int main() {
  std::string unique_name = "user_1.table_1";
  std::cout << "unique_name : " << unique_name << std::endl;

  std::size_t found = unique_name.find ('.');
  if (found != std::string::npos) {
    std::string schema_name = unique_name.substr (0, found);
    std::string class_name = unique_name.substr (found + 1);

    std::cout << "unique_name : " << unique_name << std::endl;
    std::cout << "schema_name : " << schema_name << std::endl; 
    std::cout << "class_name : " << class_name << std::endl;
  }

  std::string sql = ""
    "SELECT "
      "CASE "
        "WHEN is_system_class = 'NO' THEN LOWER (owner_name) || '.' || class_name "
        "ELSE class_name "
        "END AS unique_name, "
      "CAST ( "
          "CASE "
            "WHEN is_system_class = 'YES' THEN 0 "
            "WHEN class_type = 'CLASS' THEN 2 "
            "ELSE 1 "
            "END "
          "AS SHORT "
        "), "
      "comment "
    "FROM "
      "db_class "
    "WHERE 1 = 1 ";
  std::cout << "sql : " << sql << std::endl;

  return 0;
}
