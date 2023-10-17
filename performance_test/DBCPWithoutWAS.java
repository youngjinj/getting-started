import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;

import org.apache.commons.dbcp2.ConnectionFactory;
import org.apache.commons.dbcp2.DriverManagerConnectionFactory;
import org.apache.commons.dbcp2.PoolableConnection;
import org.apache.commons.dbcp2.PoolableConnectionFactory;
import org.apache.commons.dbcp2.PoolingDriver;
import org.apache.commons.pool2.impl.DefaultEvictionPolicy;
import org.apache.commons.pool2.impl.GenericObjectPool;
import org.apache.commons.pool2.impl.GenericObjectPoolConfig;

public class DBCPWithoutWAS {
	public static void main(String[] args) {
		DBCPWithoutWAS dbcpWithoutWAS = new DBCPWithoutWAS();

		ArrayList<Thread> threadList = new ArrayList<>();

		for (int i = 0; i < 40; i++) {
			Thread thread = new CUBRIDWorker();
			thread.start();
			threadList.add(thread);
		}

		System.out.println("---------- start ----------");

		for (int i = 0; i < threadList.size(); i++) {
			Thread thread = threadList.get(i);
			try {
				thread.join();
				// System.out.println("[end] " + thread.getName());
			} catch (InterruptedException e) {
				e.printStackTrace();
			}
		}

		System.out.println("---------- end ----------");

		dbcpWithoutWAS.destroyConnectionPool();
	}

	public DBCPWithoutWAS() {
		initConnectionPool();
	}

	public void initConnectionPool() {
		try {
			Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
		} catch (ClassNotFoundException e) {
			e.printStackTrace();
		}

		ConnectionFactory connectionFactory = new DriverManagerConnectionFactory(
				"jdbc:cubrid:192.168.37.128:33000:demodb:::", "dba", "");

		PoolableConnectionFactory poolableConnectionFactory = new PoolableConnectionFactory(connectionFactory, null);
		poolableConnectionFactory.setValidationQuery("select 1");
		poolableConnectionFactory.setValidationQueryTimeout(-1);
		poolableConnectionFactory.setPoolStatements(false);
		poolableConnectionFactory.setMaxOpenPreparedStatements(8); // DEFAULT_MAX_TOTAL_PER_KEY = 8
		poolableConnectionFactory.setMaxConnLifetimeMillis(-1);

		GenericObjectPoolConfig<PoolableConnection> genericObjectPoolConfig = new GenericObjectPoolConfig<PoolableConnection>();
		genericObjectPoolConfig.setMaxTotal(40); // DEFAULT_MAX_TOTAL = 8
		genericObjectPoolConfig.setMaxIdle(8); // DEFAULT_MAX_IDLE = 8;
		genericObjectPoolConfig.setBlockWhenExhausted(true); // DEFAULT_BLOCK_WHEN_EXHAUSTED = true
		genericObjectPoolConfig.setMaxWaitMillis(-1L); // DEFAULT_MAX_WAIT_MILLIS = -1L
		genericObjectPoolConfig.setMinIdle(0);
		genericObjectPoolConfig.setTestOnBorrow(false); // DEFAULT_TEST_ON_BORROW = false
		genericObjectPoolConfig.setTestOnReturn(false); // DEFAULT_TEST_ON_RETURN = false
		genericObjectPoolConfig.setTestOnCreate(false); // DEFAULT_TEST_ON_CREATE = false
		genericObjectPoolConfig.setTestWhileIdle(true); // DEFAULT_TEST_WHILE_IDLE = false
		genericObjectPoolConfig.setEvictionPolicyClassName(DefaultEvictionPolicy.class.getName()); // DefaultEvictionPolicy.class.getName()
		genericObjectPoolConfig.setTimeBetweenEvictionRunsMillis(-1L); // DEFAULT_TIME_BETWEEN_EVICTION_RUNS_MILLIS =
																		// -1L
		genericObjectPoolConfig.setNumTestsPerEvictionRun(3); // DEFAULT_NUM_TESTS_PER_EVICTION_RUN = 3
		genericObjectPoolConfig.setMinEvictableIdleTimeMillis(1000L * 60L * 30L); // DEFAULT_MIN_EVICTABLE_IDLE_TIME_MILLIS
																					// = 1000L * 60L * 30L
		genericObjectPoolConfig.setSoftMinEvictableIdleTimeMillis(-1); // DEFAULT_SOFT_MIN_EVICTABLE_IDLE_TIME_MILLIS =
																		// -1

		GenericObjectPool<PoolableConnection> genericObjectPool = new GenericObjectPool<PoolableConnection>(
				poolableConnectionFactory, genericObjectPoolConfig);
		poolableConnectionFactory.setPool(genericObjectPool);

		try {
			Class.forName("org.apache.commons.dbcp2.PoolingDriver");
		} catch (ClassNotFoundException e1) {
			e1.printStackTrace();
		}

		PoolingDriver poolingDriver = null;
		try {
			poolingDriver = (PoolingDriver) DriverManager.getDriver("jdbc:apache:commons:dbcp:");
			poolingDriver.registerPool("cubrid", genericObjectPool);
		} catch (SQLException e1) {
			e1.printStackTrace();
		}

		try {
			Class.forName("cubrid.jdbc.driver.CUBRIDDriver");
		} catch (ClassNotFoundException e1) {
			e1.printStackTrace();
		}
	}

	public Connection getConnection() {
		Connection connection = null;

		try {
			connection = DriverManager.getConnection("jdbc:apache:commons:dbcp:cubrid");
		} catch (SQLException e) {
			e.printStackTrace();
		}

		return connection;
	}

	public void destroyConnectionPool() {
		PoolingDriver poolingDriver = null;
		try {
			poolingDriver = (PoolingDriver) DriverManager.getDriver("jdbc:apache:commons:dbcp:");
			poolingDriver.closePool("cubrid");
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}

	public void execute() {
		try (Connection connection = getConnection()) {
			String sql = "select /*+ ordered */ ta.c1, tc.c3 from t1 ta, t2 tb, t3 tc where ta.c1 = tb.c1 and tb.c2 = tc.c1 and tc.c2 = 99999";

			try (PreparedStatement preparedStatement = connection.prepareStatement(sql.toString())) {
				Instant start = Instant.now();
				
				try (ResultSet resultSet = preparedStatement.executeQuery()) {
					while (resultSet.next()) {
						System.out.println("ta.c1 = " + resultSet.getInt(1) + ", tc.c3 = " + resultSet.getInt(2));
					}
					
					Instant end = Instant.now();
					System.out.println("execute time: " + Duration.between(start, end));
				}
			}
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}
}