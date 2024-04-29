import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;

public class CUBRIDWorker extends Thread {
	public Connection getConnection() {
		Connection connection = null;

		try {
			connection = DriverManager.getConnection("jdbc:apache:commons:dbcp:cubrid");
		} catch (SQLException e) {
			e.printStackTrace();
		}

		return connection;
	}

	@Override
	public void run() {
		try (Connection connection = getConnection()) {
			String sql = "select /*+ ordered */ ta.c1, tc.c3 from t1 ta, t2 tb, t3 tc where ta.c1 = tb.c1 and tb.c2 = tc.c1 and tc.c2 = 99999";

			try (PreparedStatement preparedStatement = connection.prepareStatement(sql.toString())) {
				Long startTime = Instant.now().toEpochMilli();

				try (ResultSet resultSet = preparedStatement.executeQuery()) {
					while (resultSet.next()) {
						/*- System.out.println("ta.c1 = " + resultSet.getInt(1) + ", tc.c3 = " + resultSet.getInt(2));
						 */
					}

					Long endTime = Instant.now().toEpochMilli();
					Long elapsedTime = endTime - startTime;
					System.out.println(elapsedTime);
				}
			}
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}
}
