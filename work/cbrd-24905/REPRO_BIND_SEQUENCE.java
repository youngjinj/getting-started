import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

public class REPRO_BIND_SEQUENCE {
	public static void main(String[] args) {
		try {
			Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
		} catch (ClassNotFoundException e) {
			e.printStackTrace();
		}

		try (Connection connection = DriverManager.getConnection("jdbc:cubrid:192.168.2.205:33000:demodb:::", "dba",
				"")) {
			try (PreparedStatement preparedStatement = connection.prepareStatement("drop table if exists t1")) {
				preparedStatement.executeUpdate();
			}

			try (PreparedStatement preparedStatement = connection
					.prepareStatement("create table t1 (c1 int, c2 int, INDEX i1 (c1, c2))")) {
				preparedStatement.executeUpdate();
			}

			try (PreparedStatement preparedStatement = connection.prepareStatement("insert into t1 values (1, 1)")) {
				preparedStatement.executeUpdate();
			}

			try (PreparedStatement preparedStatement = connection
					.prepareStatement("select count (*) from t1 where c1 = ?")) {

				/* count (*): 1 */
				int bindValue = 1;
				preparedStatement.setObject(1, bindValue);

				try (ResultSet resultSet = preparedStatement.executeQuery()) {
					while (resultSet.next()) {
						System.out.println("count (*): " + resultSet.getString(1));
					}
				}
			}

			try (PreparedStatement preparedStatement = connection
					.prepareStatement("select count (*) from t1 where c1 = ?")) {

				/* java.lang.IllegalArgumentException */
				int[] bindValueWithInt = new int[1];
				// preparedStatement.setObject(1, bindValueWithInt);

				/* Segmentation fault (core dumped) */
				Integer[] bindValueWithInteger = new Integer[1]; /* Object[] */
				preparedStatement.setObject(1, bindValueWithInteger);

				try (ResultSet resultSet = preparedStatement.executeQuery()) {
					while (resultSet.next()) {
						System.out.println("count (*): " + resultSet.getString(1));
					}
				}
			}
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}
}

