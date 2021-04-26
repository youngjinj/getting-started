import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.StringJoiner;
import java.util.UUID;

public class ExampleRND1420 {
	private final static int BIND_COUNT = 10;
	
	private static ArrayList<String> initSqls = null;
	
	private static String dropMainSql;
	private static String dropHistorySql;
	
	private static StringJoiner createMainSql = null;
	private static StringJoiner createHistorySql = null;
	private static StringJoiner createMainTriggerSql = null;
	
	private static StringJoiner errorCaseSql = null;
	private static StringJoiner errorCaseBypassSelectSql = null;
	private static StringJoiner errorCaseBypassInsertSql = null;
	
	static {
		initSqls = new ArrayList<String>();
		
		dropMainSql = "DROP TABLE IF EXISTS [main];";
		dropHistorySql = "DROP TABLE IF EXISTS [history];";
		initSqls.add(dropMainSql);
		initSqls.add(dropHistorySql);
		
		createMainSql = new StringJoiner(" ");
		createMainSql.add("CREATE TABLE [main] (");
		createMainSql.add("  [uuid] VARCHAR PRIMARY KEY,");
		createMainSql.add("  [contents] VARCHAR");
		createMainSql.add(")");
		initSqls.add(createMainSql.toString());

		createHistorySql = new StringJoiner(" ");
		createHistorySql.add("CREATE TABLE [history] (");
		createHistorySql.add("  [seq] BIGINT AUTO_INCREMENT PRIMARY KEY,");
		createHistorySql.add("  [uuid] VARCHAR,");
		createHistorySql.add("  [datetime] DATETIME,");
		createHistorySql.add("  [work] VARCHAR");
		createHistorySql.add(")");
		initSqls.add(createHistorySql.toString());
		
		createMainTriggerSql = new StringJoiner(" ");
		createMainTriggerSql.add("CREATE TRIGGER [main_trigger]");
		createMainTriggerSql.add("  BEFORE INSERT");
		createMainTriggerSql.add("  ON [main]");
		createMainTriggerSql.add("  EXECUTE AFTER");
		createMainTriggerSql.add("INSERT INTO [history] (");
		createMainTriggerSql.add("  [uuid],");
		createMainTriggerSql.add("  [datetime],");
		createMainTriggerSql.add("  [work]");
		createMainTriggerSql.add(") VALUES (");
		createMainTriggerSql.add("  [obj].[uuid],");
		createMainTriggerSql.add("  SYSDATETIME,");
		createMainTriggerSql.add("  'BATCH'");
		createMainTriggerSql.add(")");
		initSqls.add(createMainTriggerSql.toString());
		
		errorCaseSql = new StringJoiner(" ");
		errorCaseSql.add("INSERT INTO [main] (");
		errorCaseSql.add("  [uuid],");
		errorCaseSql.add("  [contents]");
		errorCaseSql.add(")");
		errorCaseSql.add("SELECT");
		errorCaseSql.add("  SYS_GUID() AS [uuid],");
		errorCaseSql.add("  SYS_GUID() AS [contests]");
		errorCaseSql.add("FROM");
		errorCaseSql.add("  db_root");
		errorCaseSql.add("WHERE");
		errorCaseSql.add("  NOT EXISTS (");
		errorCaseSql.add("    SELECT");
		errorCaseSql.add("      1");
		errorCaseSql.add("    FROM");
		errorCaseSql.add("      [main]");
		errorCaseSql.add("    WHERE");
		errorCaseSql.add("      [uuid] = ?");
		errorCaseSql.add("  )");
		
		errorCaseBypassSelectSql = new StringJoiner(" ");
		errorCaseBypassSelectSql.add("SELECT");
		errorCaseBypassSelectSql.add("  SYS_GUID() AS [uuid],");
		errorCaseBypassSelectSql.add("  SYS_GUID() AS [contests]");
		errorCaseBypassSelectSql.add("FROM");
		errorCaseBypassSelectSql.add("  db_root");
		errorCaseBypassSelectSql.add("WHERE");
		errorCaseBypassSelectSql.add("  NOT EXISTS (");
		errorCaseBypassSelectSql.add("    SELECT");
		errorCaseBypassSelectSql.add("      1");
		errorCaseBypassSelectSql.add("    FROM");
		errorCaseBypassSelectSql.add("      [main]");
		errorCaseBypassSelectSql.add("    WHERE");
		errorCaseBypassSelectSql.add("      [uuid] = ?");
		errorCaseBypassSelectSql.add("  )");
		
		errorCaseBypassInsertSql = new StringJoiner(" ");
		errorCaseBypassInsertSql.add("INSERT INTO [main] (");
		errorCaseBypassInsertSql.add("  [uuid],");
		errorCaseBypassInsertSql.add("  [contents]");
		errorCaseBypassInsertSql.add(") VALUES (");
		errorCaseBypassInsertSql.add("  ?,");
		errorCaseBypassInsertSql.add("  ?");
		errorCaseBypassInsertSql.add(")");
	}
	
	public static String getRandomUUID() {
		return UUID.randomUUID().toString().replace("-", "");
	}
	
	public static void main(String[] args) {
		try {
			Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
		} catch (ClassNotFoundException e) {
			e.printStackTrace();
		}
		
		String ip = "192.168.37.128";
		String port = "33000";
		String db = "demodb";
		String user = "dba";
		String pw = "";
		
		try (Connection connection = DriverManager.getConnection("jdbc:cubrid:" + ip + ":" + port + ":" + db + ":::", user, pw)) {
			connection.setAutoCommit(false);
			
			for (String initSql : initSqls) {
				try (PreparedStatement preparedStatement = connection.prepareStatement(initSql)) {
					preparedStatement.executeUpdate();
				} catch (SQLException e) {
					connection.rollback();
					throw e;
				}
			}
			
			connection.commit();
			
			/**
			// Error Case:
			try (PreparedStatement preparedStatement = connection.prepareStatement(errorCaseSql.toString())) {
				for (int i = 0; i < BIND_COUNT; i++) {
					preparedStatement.setString(1, ExampleRND1420.getRandomUUID());
					preparedStatement.addBatch();
					preparedStatement.clearParameters();
				}
				preparedStatement.executeBatch();
				connection.commit();
			} catch (SQLException e) {
				connection.rollback();
				throw e;
			}
			/**/
			
			/**/
			// How to bypass Error Case - 1:
			try (PreparedStatement preparedStatement1 = connection.prepareStatement(errorCaseBypassSelectSql.toString());
				 PreparedStatement preparedStatement2 = connection.prepareStatement(errorCaseBypassInsertSql.toString())) {
				for (int i = 0; i < BIND_COUNT; i++) {
					preparedStatement1.setString(1, ExampleRND1420.getRandomUUID());
					try (ResultSet resultSet = preparedStatement1.executeQuery()) {
						while (resultSet.next()) {
							preparedStatement2.setString(1, resultSet.getString("uuid"));
							preparedStatement2.setString(2, resultSet.getString("contests"));
							preparedStatement2.addBatch();
							preparedStatement2.clearParameters();
						}
					}
				}
				preparedStatement2.executeBatch();
				connection.commit();
			} catch (SQLException e) {
				connection.rollback();
				throw e;
			}
			/**/
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}
}
