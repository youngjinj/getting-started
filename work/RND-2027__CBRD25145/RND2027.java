import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.Scanner;

/*-
 * "DB_URL", "DB_ID", "DB_PW", "TEST_COUNT"은 변경이 필요합니다.
 * 
 * $ javac RND2027.java
 * $ java RND2027
 */

public class RND2027 {
	static final String DB_URL = "jdbc:cubrid:192.168.2.204:33000:demodb:::";
	static final String DB_ID = "dba";
	static final String DB_PW = "";
	static final int TEST_COUNT = 2;

	public static void main(String[] args) {
		RND2027.TestPreparedStatement();
	}

	public static void TestPreparedStatement() {
		String ddl_sql[] = { "drop table if exists test", "create table test (c1 varchar, c2 int)",
				"drop table if exists com_organizationinfo",
				"create table com_organizationinfo (orgid varchar (35) primary key, parentorgid varchar (35), orgdepth int)",
				"insert into com_organizationinfo values ('987654321', null, 1)",
				"set system parameters 'xasl_debug_dump=y';" };

		/* There is no issue with the SELECT statement. */
		String sql = "insert into test select orgid, row_number() over (order by orgdepth) rnum from com_organizationinfo a start with a.orgid = '987654321' connect by prior a.parentorgid = a.orgid";

		try {
			Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
		} catch (ClassNotFoundException e) {
			e.printStackTrace();
		}

		try (Connection connection = DriverManager.getConnection(DB_URL, DB_ID, DB_PW)) {
			for (int i = 0; i < ddl_sql.length; i++) {
				try (PreparedStatement preparedStatement = connection.prepareStatement(ddl_sql[i])) {
					preparedStatement.execute();

				}
			}

			try (PreparedStatement preparedStatement = connection.prepareStatement(sql)) {
				for (int i = 0; i < TEST_COUNT; i++) {
					System.out.println((i + 1) + "/" + TEST_COUNT + " begin...");
					(new Scanner(System.in)).nextLine();

					preparedStatement.execute();
					
					System.out.println((i + 1) + "/" + TEST_COUNT + " end");
				}

				System.out.println("complete");
			}
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}
}

